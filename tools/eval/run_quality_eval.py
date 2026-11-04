"""Does the quality gate catch bad photos? Synthetic degradations of good photos.

Takes every photo whose gate verdict is 'ok' (see run_face_eval.py), applies a
KNOWN degradation at 4 strengths, and counts how many degraded copies the gate
flags (warn or reject). It checks the gate against degradations we made
ourselves; it does NOT show how it behaves on real bad selfies.

    tools/.venv/bin/python tools/eval/run_quality_eval.py [photos_dir] [out_dir]
"""
import csv
import glob
import os
import sys

import cv2
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import face_zones as fz
import photo_quality as pq

HERE = os.path.dirname(os.path.abspath(__file__))


def blur(f):
    def run(bgr, face_w):
        s = f * face_w
        return cv2.GaussianBlur(bgr, (0, 0), s)
    return run


def gamma(g):
    lut = np.array([255 * (i / 255) ** g for i in range(256)], np.uint8)
    return lambda bgr, face_w: cv2.LUT(bgr, lut)


def gain(k):
    return lambda bgr, face_w: np.clip(bgr.astype(np.float32) * k, 0, 255).astype(np.uint8)


def shrink(target_w):
    def run(bgr, face_w):
        s = target_w / face_w
        small = cv2.resize(bgr, None, fx=s, fy=s, interpolation=cv2.INTER_AREA)
        return small
    return run


KINDS = {
    'blur (sigma = 0.4/0.8/1.6/3% of face width)': [blur(f) for f in (0.004, 0.008, 0.016, 0.03)],
    'too dark (gamma 1.5/2/2.5/3)': [gamma(g) for g in (1.5, 2.0, 2.5, 3.0)],
    'overexposed (gain 1.3/1.6/2/2.5)': [gain(k) for k in (1.3, 1.6, 2.0, 2.5)],
    'small face (face width 140/110/80/50 px)': [shrink(w) for w in (140, 110, 80, 50)],
}


def main(src, out):
    os.makedirs(out, exist_ok=True)
    zoner = fz.FaceZoner()
    base = []
    originals = {'ok': 0, 'warn': 0, 'reject': 0}
    for f in sorted(glob.glob(os.path.join(src, '*.jpg'))):
        bgr = cv2.imread(f)
        res = zoner.detect(bgr)
        q = pq.judge(pq.measure(bgr, res.points), res.n_faces)
        originals[q.verdict] += 1
        if q.verdict == 'ok':
            base.append((os.path.basename(f), bgr, float(np.linalg.norm(res.points[454, :2] - res.points[234, :2]))))
    print('originals:', originals, '-> base set for degradation:', len(base))
    rows = []
    for kind, fns in KINDS.items():
        for lvl, fn in enumerate(fns, 1):
            flagged = rejected = noface = 0
            trig = {}
            for name, bgr, fw in base:
                q = pq.assess(fn(bgr, fw), zoner)
                flagged += q.verdict != 'ok'
                rejected += q.verdict == 'reject'
                noface += any('no face' in r for r in q.reasons)
                for r in q.reasons:
                    k = r.split(': ', 1)[1].split(' ')[0:2]
                    trig[' '.join(k)] = trig.get(' '.join(k), 0) + 1
            rows.append(dict(kind=kind, level=lvl, n=len(base), flagged=flagged, rejected=rejected,
                             no_face=noface, triggers='; '.join(f'{k} x{v}' for k, v in sorted(trig.items()))))
            print(rows[-1])
    with open(os.path.join(out, 'quality_synthetic.csv'), 'w', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    with open(os.path.join(out, 'quality_originals.txt'), 'w') as fh:
        fh.write(f'originals verdicts: {originals}\nbase set (verdict ok): {len(base)}\n')


if __name__ == '__main__':
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'data', 'photos')
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, 'out', 'face')
    main(src, out)
