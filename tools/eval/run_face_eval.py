"""Zones + quality gate over the evaluation photos, with timing.

    tools/.venv/bin/python tools/eval/run_face_eval.py [photos_dir] [out_dir]

Writes into out_dir (default tools/eval/out/face):
  zones_stats.csv, quality.csv  one row per photo
  <photo>_zones.jpg             overlays to LOOK at (this is the visual check)
  sheet_N.jpg                   contact sheets of the overlays
  timing.txt                    latency of detection and of the quality metrics
"""
import csv
import glob
import os
import statistics
import sys
import time

import cv2
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import face_zones as fz
import photo_quality as pq

HERE = os.path.dirname(os.path.abspath(__file__))
RUNS = 10


def main(src, out):
    os.makedirs(out, exist_ok=True)
    zoner = fz.FaceZoner()
    files = sorted(sum((glob.glob(os.path.join(src, e)) for e in ('*.jpg', '*.jpeg', '*.png')), []))
    zrows, qrows, tiles = [], [], []
    det_ms, mask_ms, q_ms = [], [], []
    for f in files:
        name = os.path.splitext(os.path.basename(f))[0]
        bgr = cv2.imread(f)
        res = zoner.detect(bgr)
        if res is None:
            zrows.append(dict(photo=name, faces=0))
            qrows.append(dict(photo=name, verdict='reject', reasons='no face found'))
            continue
        # timing: warm run is the detect above; now RUNS timed repeats
        for _ in range(RUNS):
            r = zoner.detect(bgr)
            det_ms.append(r.inference_ms)
        t = time.perf_counter()
        for _ in range(RUNS):
            masks = fz.zone_masks(res.points, bgr.shape)
        mask_ms.append((time.perf_counter() - t) / RUNS * 1000)
        t = time.perf_counter()
        for _ in range(RUNS):
            m = pq.measure(bgr, res.points)
        q_ms.append((time.perf_counter() - t) / RUNS * 1000)
        q = pq.judge(m, res.n_faces)
        face_area = int((fz.face_mask(res.points, bgr.shape) > 0).sum())
        z = dict(photo=name, faces=res.n_faces, face_w_px=m['face_px'],
                 yaw_offset=m['yaw_offset'], roll_deg=m['roll_deg'])
        for zn, mk in masks.items():
            z[f'{zn}_pct_of_face'] = round(float(100 * (mk > 0).sum() / face_area), 1)
        zrows.append(z)
        qrows.append(dict(photo=name, verdict=q.verdict, **{k: v for k, v in m.items()},
                          reasons=' | '.join(q.reasons)))
        vis = fz.draw_overlay(bgr, res.points, masks)
        cv2.imwrite(os.path.join(out, f'{name}_zones.jpg'), vis)
        x0, y0 = res.points[:, :2].min(0).astype(int)
        x1, y1 = res.points[:, :2].max(0).astype(int)
        pad = int(0.15 * (x1 - x0))
        crop = vis[max(0, y0 - pad):y1 + pad, max(0, x0 - pad):x1 + pad]
        s = 360 / max(crop.shape[:2])
        crop = cv2.resize(crop, None, fx=s, fy=s)
        tile = np.full((380, 360, 3), 255, np.uint8)
        tile[:crop.shape[0], :crop.shape[1]] = crop
        cv2.putText(tile, name, (4, 374), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 255), 2)
        tiles.append(tile)
        print(name, q.verdict, '; '.join(q.reasons))

    def dump(path, rows):
        keys = []
        for r in rows:
            keys += [k for k in r if k not in keys]
        with open(path, 'w', newline='') as fh:
            w = csv.DictWriter(fh, fieldnames=keys)
            w.writeheader()
            w.writerows(rows)
    dump(os.path.join(out, 'zones_stats.csv'), zrows)
    dump(os.path.join(out, 'quality.csv'), qrows)
    for s in range(0, len(tiles), 12):
        chunk = tiles[s:s + 12]
        while len(chunk) % 4:
            chunk.append(np.full((380, 360, 3), 255, np.uint8))
        cv2.imwrite(os.path.join(out, f'sheet_{s // 12}.jpg'),
                    np.vstack([np.hstack(chunk[i:i + 4]) for i in range(0, len(chunk), 4)]))

    def stat(xs):
        xs = sorted(xs)
        return (f'mean {statistics.mean(xs):.1f}  median {statistics.median(xs):.1f}  '
                f'p95 {xs[int(0.95 * (len(xs) - 1))]:.1f}  max {xs[-1]:.1f}')
    n_found = sum(1 for r in zrows if r.get('faces'))
    lines = [f'photos: {len(files)}, face found: {n_found}',
             f'timed repeats per photo: {RUNS} (after one warm-up run)',
             f'Face Landmarker detect, ms per photo ({len(det_ms)} runs): ' + stat(det_ms),
             f'zone masks, ms per photo ({len(mask_ms)} photos): ' + stat(mask_ms),
             f'quality metrics, ms per photo ({len(q_ms)} photos): ' + stat(q_ms),
             f'cv2 {cv2.__version__}']
    open(os.path.join(out, 'timing.txt'), 'w').write('\n'.join(lines) + '\n')
    print('\n'.join(lines))


if __name__ == '__main__':
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'data', 'photos')
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, 'out', 'face')
    main(src, out)
