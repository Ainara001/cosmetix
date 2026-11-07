"""Tests for the parts of the stand that are not metric formulas: input files,
head pose, the quality gate, photo verification. Run:
    tools/.venv/bin/python -m unittest discover tools/eval/tests
"""
import math
import os
import sys
import tempfile
import unittest

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
import face_zones as fz
import fetch_photos
import photo_quality as pq
import skin_eval as se


def mesh(roll_deg=0.0, nose_offset=0.0):
    """Minimal fake landmarks: a face 100 px wide, eyes at +-30, nose at the middle + offset."""
    p = np.zeros((478, 3))
    p[234] = (-50, 0, 0)
    p[454] = (50, 0, 0)
    p[33] = (-30, -10, 0)
    p[263] = (30, -10, 0)
    p[4] = (100 * nose_offset, 20, 0)
    a = math.radians(roll_deg)
    R = np.array([[math.cos(a), -math.sin(a)], [math.sin(a), math.cos(a)]])
    p[:, :2] = p[:, :2] @ R.T
    return p


class HeadPoseTests(unittest.TestCase):
    def test_frontal(self):
        self.assertAlmostEqual(fz.head_pose(mesh())['yaw_offset'], 0.0, places=6)

    def test_roll_is_not_yaw(self):
        # a frontal face tilted by 25 degrees must still read as frontal
        pose = fz.head_pose(mesh(roll_deg=25))
        self.assertAlmostEqual(pose['yaw_offset'], 0.0, places=6)
        self.assertAlmostEqual(pose['roll_deg'], 25.0, places=4)

    def test_turn_is_detected_with_and_without_roll(self):
        self.assertAlmostEqual(fz.head_pose(mesh(nose_offset=0.3))['yaw_offset'], 0.3, places=6)
        self.assertAlmostEqual(fz.head_pose(mesh(roll_deg=-20, nose_offset=0.3))['yaw_offset'], 0.3, places=6)


def good():
    return {'face_px': 400.0, 'sharpness': 300.0, 'skin_L_mean': 60.0, 'face_p95_luma': 200.0, 'skin_chroma': 15.0,
            'clipped_pct': 0.0, 'crushed_pct': 0.0, 'lr_asym': 0.05, 'yaw_offset': 0.03, 'roll_deg': 0.0}


class GateTests(unittest.TestCase):
    def test_good_photo_is_ok(self):
        self.assertEqual(pq.judge(good()).verdict, 'ok')

    def test_each_defect_is_flagged(self):
        for key, bad, expect in [('sharpness', 10.0, 'reject'), ('sharpness', 40.0, 'warn'),
                                 ('face_px', 90.0, 'reject'), ('face_px', 130.0, 'warn'),
                                 ('face_p95_luma', 70.0, 'reject'), ('face_p95_luma', 100.0, 'warn'),
                                 ('clipped_pct', 20.0, 'reject'), ('clipped_pct', 6.0, 'warn'),
                                 ('yaw_offset', 0.35, 'reject'), ('yaw_offset', 0.2, 'warn'),
                                 ('skin_chroma', 0.0, 'reject'), ('skin_chroma', 2.5, 'warn'),
                                 ('lr_asym', 5.0, 'warn')]:
            m = good()
            m[key] = bad
            self.assertEqual(pq.judge(m).verdict, expect, (key, bad))

    def test_side_light_never_rejects(self):
        m = good()
        m['lr_asym'] = 100.0
        self.assertEqual(pq.judge(m).verdict, 'warn')

    def test_nan_asymmetry_is_ignored_and_several_faces_warn(self):
        m = good()
        m['lr_asym'] = float('nan')
        self.assertEqual(pq.judge(m).verdict, 'ok')
        self.assertEqual(pq.judge(good(), n_faces=2).verdict, 'warn')

    def test_another_face_rejects_a_small_one_only_warns(self):
        for ratio, expect in [(0.0, 'ok'), (0.05, 'warn'), (0.10, 'reject'), (0.9, 'reject')]:
            m = good()
            m['second_face_ratio'] = ratio
            self.assertEqual(pq.judge(m).verdict, expect, ratio)
        m = good()
        m['second_face_ratio'] = 0.9
        self.assertEqual(pq.judge(m, n_faces=2).reasons.count('warn: 2 faces in the frame, only the first is analysed'), 0)

    def test_dark_flat_eyes_warn_but_open_or_closed_eyes_do_not(self):
        for dark, flat, expect in [(0.3, 0.04, 'warn'),        # dark lenses or a squint: a warning, never a refusal
                                   (0.3, 0.12, 'ok'),          # dark but with a visible eye
                                   (0.95, 0.03, 'ok'),         # closed lids: as bright as the cheeks
                                   (float('nan'), float('nan'), 'ok')]:
            m = good()
            m['eye_dark_ratio'], m['eye_contrast'] = dark, flat
            self.assertEqual(pq.judge(m).verdict, expect, (dark, flat))

    def test_little_visible_skin_only_warns(self):
        m = good()
        m['skin_visible'] = 0.1
        self.assertEqual(pq.judge(m).verdict, 'warn')
        m['skin_visible'] = float('nan')
        self.assertEqual(pq.judge(m).verdict, 'ok')

    def test_worst_verdict_wins(self):
        m = good()
        m['sharpness'], m['yaw_offset'] = 40.0, 0.35
        q = pq.judge(m)
        self.assertEqual(q.verdict, 'reject')
        self.assertEqual(len(q.reasons), 2)


class InputFileTests(unittest.TestCase):
    def write(self, text, bom=False):
        d = tempfile.mkdtemp()
        p = os.path.join(d, 'f.csv')
        with open(p, 'w', encoding='utf-8-sig' if bom else 'utf-8', newline='') as fh:
            fh.write(text)
        return p

    def test_bom_and_spaces_are_ok(self):
        rows = se.read_csv(self.write('image, acne\n a.jpg ,1\nb.jpg,0\n', bom=True))
        self.assertEqual(set(rows), {'a.jpg', 'b.jpg'})
        self.assertEqual(rows['a.jpg']['acne'], '1')

    def test_errors_name_the_line(self):
        with self.assertRaisesRegex(se.DataError, 'f.csv:3: duplicate'):
            se.read_csv(self.write('image,acne\na.jpg,1\na.jpg,0\n'))
        with self.assertRaisesRegex(se.DataError, 'no "image" column'):
            se.read_csv(self.write('name,acne\na.jpg,1\n'))
        labels = se.read_csv(self.write('image,acne,severity\na.jpg,1,mild\n'))
        preds = {'a.jpg': {'acne': '1', 'severity': '1', '_line': 2}}
        with self.assertRaisesRegex(se.DataError, 'labels line 2.*mild'):
            se.evaluate(labels, preds)

    def test_float_style_values_are_accepted(self):
        labels = {'a': {'acne': '1.0', 'severity': '2.0', '_line': 2}}
        preds = {'a': {'acne': '0.0', 'severity': '2', '_line': 2}}
        r = se.evaluate(labels, preds)
        self.assertEqual(r['classes']['acne']['fn'], 1)
        self.assertEqual(r['severity']['accuracy'], 1.0)

    def test_no_matching_names_is_an_error(self):
        with self.assertRaisesRegex(se.DataError, 'no image name'):
            se.evaluate({'a.jpg': {'acne': '1'}}, {'photos/a.jpeg': {'acne': '1'}})


class KappaTests(unittest.TestCase):
    def test_missing_level_does_not_change_kappa(self):
        pairs = [(0, 0), (1, 1), (3, 1), (3, 3), (1, 3), (0, 1)] * 3
        self.assertAlmostEqual(se.weighted_kappa(pairs, [0, 1, 3]), se.weighted_kappa(pairs, [0, 1, 2, 3]), places=9)


class PhotoCheckTests(unittest.TestCase):
    def test_jpeg_and_hash_checks(self):
        import hashlib
        jpeg = b'\xff\xd8\xff\xe0' + b'x' * 20
        self.assertIsNone(fetch_photos.problem(jpeg, None))
        self.assertIsNone(fetch_photos.problem(jpeg, hashlib.sha256(jpeg).hexdigest()))
        self.assertIn('differs', fetch_photos.problem(jpeg, '0' * 64))
        self.assertIn('not a JPEG', fetch_photos.problem(b'<html>error</html>', None))


if __name__ == '__main__':
    unittest.main()
