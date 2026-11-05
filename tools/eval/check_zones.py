"""Zone overlay check: draws zones on every photo and writes a contact sheet.

    tools/.venv/bin/python tools/eval/check_zones.py tools/eval/data/photos out_dir
"""
import csv
import glob
import os
import sys

import cv2

sys.path.insert(0, os.path.dirname(__file__))
import face_zones as fz
import viz


def main(src, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    zoner = fz.FaceZoner()
    files = sorted(sum((glob.glob(os.path.join(src, e)) for e in ('*.jpg', '*.jpeg', '*.png')), []))
    rows, tiles = [], []
    for f in files:
        bgr = cv2.imread(f)
        name = os.path.splitext(os.path.basename(f))[0]
        res = zoner.detect(bgr)
        if res is None:
            rows.append(dict(photo=name, faces=0))
            print(name, 'NO FACE')
            continue
        masks = fz.zone_masks(res.points, bgr.shape)
        face_area = int((fz.face_mask(res.points, bgr.shape) > 0).sum())
        vis = fz.draw_overlay(bgr, res.points, masks)
        cv2.imwrite(os.path.join(out_dir, f'{name}_zones.jpg'), vis)
        pose = fz.head_pose(res.points)
        row = dict(photo=name, faces=res.n_faces, ms=round(res.inference_ms, 1), face_px=face_area,
                   yaw_offset=round(pose['yaw_offset'], 3), roll_deg=round(pose['roll_deg'], 1))
        for z, m in masks.items():
            row[f'{z}_pct'] = round(float(100 * (m > 0).sum() / face_area), 1)
        rows.append(row)
        print(' '.join(f'{k}={v}' for k, v in row.items()))
        tiles.append(viz.make_tile(vis, res.points, name))
    keys = sorted({k for r in rows for k in r})
    with open(os.path.join(out_dir, 'zones_stats.csv'), 'w', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=keys)
        w.writeheader()
        w.writerows(rows)
    viz.save_sheets(tiles, out_dir)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
