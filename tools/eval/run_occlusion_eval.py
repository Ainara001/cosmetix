"""Does the gate see covered faces? Synthetic occluders on development photos.

Takes the main-set photos the gate accepts, paints an occluder onto each one using the
face landmarks, and counts how many copies the gate rejects or warns about:

  sunglasses   opaque dark lenses over both eyes (several darknesses)
  mask         a light-blue face mask over nose, mouth and chin
  scarf        a skin-coloured-NOT patch is not used; a mid-grey scarf over the lower face
  hand         a patch of THIS face's own skin colour over one cheek (expected to be missed:
               a hand has the colour of the face)
  second face  the same face pasted small next to the main one

It checks the rules against occluders WE drew; it says nothing about real glasses (they reflect,
have frames and clear parts) or real hands. Unmodified copies give the false-alarm baseline.

    tools/.venv/bin/python tools/eval/run_occlusion_eval.py [photos_dir]
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


def _poly(img, pts, color):
    cv2.fillPoly(img, [np.round(pts).astype(np.int32)], color)


def sunglasses(img, p, gray):
    out = img.copy()
    # one lens per eye, generously larger than the eye opening, plus the bridge
    for loop in (fz.EYE_RIGHT, fz.EYE_LEFT):
        pts = p[loop, :2]
        c = pts.mean(0)
        _poly(out, c + (pts - c) * 1.9, (gray, gray, gray))
    _poly(out, np.array([p[133, :2], p[362, :2], p[362, :2] + [0, 12], p[133, :2] + [0, 12]]), (gray, gray, gray))
    return out


def mask(img, p):
    out = img.copy()
    loop = [234, 93, 132, 58, 172, 136, 150, 149, 176, 148, 152, 377, 400, 378, 379, 365, 397, 288, 361, 323, 454]
    top = [p[168, :2]]
    _poly(out, np.vstack([p[loop, :2], top]), (200, 170, 120))   # BGR: light blue
    return out


def scarf(img, p):
    out = img.copy()
    loop = [234, 93, 132, 58, 172, 136, 150, 149, 176, 148, 152, 377, 400, 378, 379, 365, 397, 288, 361, 323, 454]
    _poly(out, np.vstack([p[loop, :2], [p[4, :2]]]), (110, 110, 110))
    return out


def hand(img, p, masks):
    out = img.copy()
    zone = masks['cheek_left'] > 0
    med = np.median(img[zone], axis=0)
    out[zone] = med           # a flat patch of the face's own colour
    return out


def second_face(img, p):
    out = img.copy()
    x0, y0 = np.floor(p[fz.FACE_OVAL, :2].min(0)).astype(int)
    x1, y1 = np.ceil(p[fz.FACE_OVAL, :2].max(0)).astype(int)
    crop = img[max(0, y0):y1, max(0, x0):x1]
    if crop.size == 0:
        return out
    h, w = out.shape[:2]
    s = 0.6                    # second face 60 % of the main one
    small = cv2.resize(crop, None, fx=s, fy=s)
    ox = min(w - small.shape[1], x1 + 10) if x1 + small.shape[1] + 10 < w else max(0, x0 - small.shape[1] - 10)
    oy = max(0, min(h - small.shape[0], y0))
    if ox < 0 or ox + small.shape[1] > w:
        return out
    out[oy:oy + small.shape[0], ox:ox + small.shape[1]] = small
    return out


CASES = {
    'sunglasses (dark 15)': lambda img, p, m: sunglasses(img, p, 15),
    'sunglasses (dark 40)': lambda img, p, m: sunglasses(img, p, 40),
    'sunglasses (grey 80)': lambda img, p, m: sunglasses(img, p, 80),
    'mask': lambda img, p, m: mask(img, p),
    'scarf': lambda img, p, m: scarf(img, p),
    'hand (face colour)': lambda img, p, m: hand(img, p, m),
    'second face (60 %)': lambda img, p, m: second_face(img, p),
}


def main(src):
    zoner = fz.FaceZoner()
    base = []
    for f in sorted(glob.glob(os.path.join(src, '*.jpg'))):
        bgr = cv2.imread(f)
        r = zoner.detect(bgr)
        if r is None:
            continue
        q = pq.judge(pq.measure(bgr, r.points, None, r.other_widths), r.n_faces)
        if q.verdict != 'reject':
            base.append((os.path.basename(f)[:-4], bgr, r))
    print('base photos the gate accepts:', len(base))
    rows = [dict(case='unmodified', n=len(base), rejected=0, warned=0, no_face=0)]
    for name, b, r in base:
        q = pq.judge(pq.measure(b, r.points, None, r.other_widths), r.n_faces)
        rows[0]['warned'] += q.verdict == 'warn'
    for case, fn in CASES.items():
        rej = warn = nof = 0
        for name, bgr, r in base:
            masks = fz.zone_masks(r.points, bgr.shape)
            img = fn(bgr, r.points, masks)
            res = zoner.detect(img)
            if res is None:
                nof += 1
                continue
            q = pq.judge(pq.measure(img, res.points, None, res.other_widths), res.n_faces)
            rej += q.verdict == 'reject'
            warn += q.verdict == 'warn'
        rows.append(dict(case=case, n=len(base), rejected=rej, warned=warn, no_face=nof))
    for r in rows:
        print(r)
    os.makedirs(os.path.join(HERE, 'out'), exist_ok=True)
    with open(os.path.join(HERE, 'out', 'occlusion_synthetic.csv'), 'w', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'data', 'photos'))
