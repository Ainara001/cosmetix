"""How much does the answer depend on white balance, light and filters?

Takes photos, applies known changes that a camera or an app could make (a white-balance
cast, darker, brighter, a beauty filter) and compares:

  LOCAL    skin colour measured on the face zones: Lab L*, a*, b* and the individual
           typology angle ITA = atan((L*-50)/b*) in degrees (median over the zones).
           Landmarks are reused from the original: the changes are global and keep geometry.
  GEMINI   (with --gemini) the app's own prompt on every changed copy: do skinTone,
           undertone, colorType stay the same as for the original?

A pure white-balance error changes the camera, not the person, so an answer that flips is
an answer that depends on the camera. This measures SENSITIVITY, not accuracy: there is no
reference label here for what the right answer is.

    tools/.venv/bin/python tools/eval/run_wb_sensitivity.py p007 p114 ... [--gemini]
"""
import argparse
import base64
import csv
import json
import os
import sys
import time

import cv2
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import face_zones as fz
import gemini_repeat as gr
import transforms as tf

HERE = os.path.dirname(os.path.abspath(__file__))
CONDITIONS = {
    'original': lambda b, w=None: b,
    'warm cast (R x1.15, B x0.85)': tf.cast(1.15, 1.0, 0.85),
    'cool cast (R x0.85, B x1.15)': tf.cast(0.85, 1.0, 1.15),
    'strong warm cast (R x1.35, B x0.70)': tf.cast(1.35, 1.0, 0.70),
    'strong cool cast (R x0.70, B x1.35)': tf.cast(0.70, 1.0, 1.35),
    'darker (gamma 1.6)': tf.gamma(1.6),
    'brighter (gain 1.25)': tf.gain(1.25),
    'beauty filter (smooth, sat x1.4, warm tint)': tf.beauty_filter(),
}


def skin_lab(bgr, masks):
    """Median L*, a*, b* (CIELAB, L 0-100, a/b centred) over the skin zones."""
    lab = cv2.cvtColor(bgr, cv2.COLOR_BGR2LAB).astype(np.float32)
    skin = np.zeros(bgr.shape[:2], bool)
    for m in masks.values():
        skin |= m > 0
    L = np.median(lab[:, :, 0][skin]) * 100.0 / 255.0
    a = np.median(lab[:, :, 1][skin]) - 128.0
    b = np.median(lab[:, :, 2][skin]) - 128.0
    ita = float(np.degrees(np.arctan2(L - 50.0, b)))
    return float(L), float(a), float(b), ita


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('photos', nargs='+')
    ap.add_argument('--set', default='photos')
    ap.add_argument('--gemini', action='store_true')
    ap.add_argument('--base', default='http://127.0.0.1:8799')
    ap.add_argument('--pause', type=float, default=3.5)
    ap.add_argument('--out', default=os.path.join(HERE, 'out', 'wb'))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    zoner = fz.FaceZoner()
    prompt = gr.app_prompt() + '\nRequested language: Russian.'
    rows = []
    for pid in a.photos:
        bgr = cv2.imread(os.path.join(HERE, 'data', a.set, pid + '.jpg'))
        res = zoner.detect(bgr)
        masks = fz.zone_masks(res.points, bgr.shape)
        base = {}
        for cname, fn in CONDITIONS.items():
            img = fn(bgr)
            L, A, B, ita = skin_lab(img, masks)
            row = dict(photo=pid, condition=cname, L=round(L, 1), a=round(A, 1), b=round(B, 1), ita=round(ita, 1))
            if a.gemini:
                status, data, ms = gr.call(a.base, prompt, base64.b64encode(tf.jpeg_bytes(img)).decode())
                obj = gr.parse(data.get('text', '')) if status == 200 else None
                c = gr.canon(obj) if obj else {}
                row.update(status=status, ms=round(ms), conf=(obj or {}).get('confidence'), **c)
                time.sleep(a.pause)
            if cname == 'original':
                base = row
            row['d_L'] = round(row['L'] - base['L'], 1)
            row['d_b'] = round(row['b'] - base['b'], 1)
            row['d_ita'] = round(row['ita'] - base['ita'], 1)
            rows.append(row)
            print({k: row[k] for k in row if k in ('photo', 'condition', 'ita', 'd_ita', 'skinTone', 'undertone', 'colorType', 'conf')})
    keys = []
    for r in rows:
        keys += [k for k in r if k not in keys]
    with open(os.path.join(a.out, 'wb.csv'), 'w', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=keys)
        w.writeheader()
        w.writerows(rows)


if __name__ == '__main__':
    main()
