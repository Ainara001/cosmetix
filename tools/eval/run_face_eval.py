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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import face_zones as fz
import photo_quality as pq
import viz

HERE = os.path.dirname(os.path.abspath(__file__))
RUNS = 10


def main(src, out, runs=RUNS):
    global RUNS
    RUNS = runs
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
            m = pq.measure(bgr, res.points, masks, res.other_widths)
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
        tiles.append(viz.make_tile(vis, res.points, name))
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
    viz.save_sheets(tiles, out)

    def stat(xs):
        if not xs:
            return 'n/a (no face found)'
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
    main(src, out, int(sys.argv[3]) if len(sys.argv) > 3 else RUNS)
