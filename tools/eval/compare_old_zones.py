"""Share of the face oval taken by the DRAFT zones (convex hulls of the index lists in the old
tools/mediapipe_face_zones_check.py) against the current zones, on the frontal photos
(yaw_offset <= 0.075) of the main set. Needs out/face/zones_stats.csv from run_face_eval.py.

    tools/.venv/bin/python tools/eval/compare_old_zones.py
"""
import csv
import glob
import json
import os
import sys

import cv2
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import face_zones as fz

HERE = os.path.dirname(os.path.abspath(__file__))
OLD = {
    'forehead': [54, 103, 67, 109, 10, 338, 297, 332, 284, 333, 298, 301, 300, 293, 334, 296, 336, 9, 107, 66, 105, 63, 70, 156],
    'cheek_right': [116, 117, 118, 119, 100, 142, 203, 206, 216, 207, 187, 147, 123, 50, 101, 36, 205],
    'cheek_left': [345, 346, 347, 348, 329, 371, 423, 426, 436, 427, 411, 376, 352, 280, 330, 266, 425],
    'nose': [6, 197, 195, 5, 4, 1, 19, 94, 2, 98, 97, 326, 327, 168, 193, 417, 122, 351, 196, 419, 3, 51, 45, 275, 281, 248],
    'chin': [152, 377, 400, 378, 379, 365, 397, 288, 361, 323, 454, 175, 171, 148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 18, 200, 199, 208, 428],
}


def main():
    rows = list(csv.DictReader(open(os.path.join(HERE, 'out', 'face', 'zones_stats.csv'))))
    frontal = {r['photo']: r for r in rows if r.get('yaw_offset') and float(r['yaw_offset']) <= 0.075}
    zoner = fz.FaceZoner()
    old = {k: [] for k in OLD}
    new = {k: [] for k in OLD}
    for name, r in frontal.items():
        b = cv2.imread(os.path.join(HERE, 'data', 'photos', name + '.jpg'))
        res = zoner.detect(b)
        face = (fz.face_mask(res.points, b.shape) > 0).sum()
        for k, idx in OLD.items():
            m = np.zeros(b.shape[:2], np.uint8)
            cv2.fillConvexPoly(m, cv2.convexHull(res.points[idx, :2].astype(np.int32)), 255)
            old[k].append(100.0 * (m > 0).sum() / face)
            new[k].append(float(r[k + '_pct_of_face']))
    out = {'photos': len(frontal)}
    for k in OLD:
        out[k] = {'old_mean': float(np.mean(old[k])), 'old_min': float(min(old[k])), 'old_max': float(max(old[k])),
                  'new_mean': float(np.mean(new[k])), 'new_min': float(min(new[k])), 'new_max': float(max(new[k]))}
        print(k, {a: round(b, 1) for a, b in out[k].items()})
    json.dump(out, open(os.path.join(HERE, 'out', 'old_vs_new_zones.json'), 'w'), indent=1)


if __name__ == '__main__':
    main()
