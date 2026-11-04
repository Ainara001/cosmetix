"""Photo quality gate (OpenCV): is this selfie good enough to analyse?

Metrics are computed on the FACE, not the whole frame, so a sharp background
cannot hide a blurry face:

  face_px         face width in pixels (too small = no detail)
  sharpness       variance of the Laplacian of the face crop, rescaled to a fixed
                  face width so the number does not depend on the photo size
  skin_L_mean     mean CIELAB L* (0-100) over the skin zones (reported only: it
                  depends on the person's skin tone, so it is not used to judge)
  face_p95_luma   95th percentile of luma (0-255) inside the face oval: how bright
                  the brightest part of the face is. A dark room gives a low value
                  whatever the skin tone, which is why it is used instead of the mean
  clipped_pct     % of skin-zone pixels at/over CLIP_LUMA (blown highlights)
  crushed_pct     % of skin-zone pixels at/under CRUSH_LUMA (lost in the shadows)
  lr_asym         |left cheek - right cheek| mean L* / mean of both (side light)
  yaw_offset      head turn, see face_zones.head_pose

The thresholds below are HEURISTICS chosen from the 24 photos in
tools/eval/photos_manifest.json and from synthetic degradations
(tools/eval/run_quality_eval.py). They are not validated on real user selfies.
"""
from __future__ import annotations

from dataclasses import dataclass, field

import cv2
import numpy as np

import face_zones as fz

NORM_FACE_W = 300          # face width the sharpness is measured at
CLIP_LUMA = 250
CRUSH_LUMA = 12

# (warn, reject)
T = {
    'face_px_min': (160, 100),       # below warn: little detail; below reject: not usable
    'sharpness_min': (60.0, 25.0),
    'face_p95_luma_min': (110, 80),
    'clipped_pct_max': (4.0, 12.0),
    'crushed_pct_max': (25.0, 50.0),
    'lr_asym_max': (0.35, float('inf')),   # side light: warn only, never reject
    'yaw_offset_max': (0.15, 0.25),
}


@dataclass
class Quality:
    metrics: dict = field(default_factory=dict)
    verdict: str = 'ok'              # ok | warn | reject
    reasons: list = field(default_factory=list)


def _lab_L(bgr):
    return cv2.cvtColor(bgr, cv2.COLOR_BGR2LAB)[:, :, 0].astype(np.float32) * (100.0 / 255.0)


def measure(bgr: np.ndarray, points: np.ndarray) -> dict:
    masks = fz.zone_masks(points, bgr.shape)
    skin = np.zeros(bgr.shape[:2], np.uint8)
    for m in masks.values():
        skin |= m
    face_w = float(np.linalg.norm(points[454, :2] - points[234, :2]))
    # sharpness: face bbox crop, rescaled so the face is NORM_FACE_W wide
    x0, y0 = np.floor(points[fz.FACE_OVAL, :2].min(0)).astype(int)
    x1, y1 = np.ceil(points[fz.FACE_OVAL, :2].max(0)).astype(int)
    x0, y0 = max(0, x0), max(0, y0)
    crop = cv2.cvtColor(bgr[y0:y1, x0:x1], cv2.COLOR_BGR2GRAY)
    s = NORM_FACE_W / face_w
    crop = cv2.resize(crop, None, fx=s, fy=s, interpolation=cv2.INTER_AREA if s < 1 else cv2.INTER_CUBIC)
    sharp = float(cv2.Laplacian(crop, cv2.CV_64F).var())
    L = _lab_L(bgr)
    luma = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    sk = skin > 0
    n = max(1, int(sk.sum()))
    cl, cr = masks['cheek_left'] > 0, masks['cheek_right'] > 0
    lr = np.nan
    if cl.sum() > 50 and cr.sum() > 50:
        a, b = float(L[cl].mean()), float(L[cr].mean())
        lr = abs(a - b) / max(1e-6, (a + b) / 2)
    pose = fz.head_pose(points)
    return {
        'face_px': round(face_w, 1),
        'sharpness': round(sharp, 1),
        'skin_L_mean': round(float(L[sk].mean()), 1) if sk.any() else float('nan'),
        'face_p95_luma': round(float(np.percentile(luma[fz.face_mask(points, bgr.shape) > 0], 95)), 1),
        'clipped_pct': round(100.0 * float((luma[sk] >= CLIP_LUMA).sum()) / n, 2),
        'crushed_pct': round(100.0 * float((luma[sk] <= CRUSH_LUMA).sum()) / n, 2),
        'lr_asym': round(float(lr), 3) if lr == lr else float('nan'),
        'yaw_offset': round(pose['yaw_offset'], 3),
        'roll_deg': round(pose['roll_deg'], 1),
    }


def judge(m: dict, n_faces: int = 1) -> Quality:
    q = Quality(metrics=m)
    sev = {'ok': 0, 'warn': 1, 'reject': 2}

    def flag(level, text):
        q.reasons.append(f'{level}: {text}')
        if sev[level] > sev[q.verdict]:
            q.verdict = level

    if n_faces > 1:
        flag('warn', f'{n_faces} faces in the frame, only the first is analysed')

    def low(key, label, val):
        w, r = T[key]
        if val < r:
            flag('reject', f'{label} {val} < {r}')
        elif val < w:
            flag('warn', f'{label} {val} < {w}')

    def high(key, label, val):
        if val != val:   # NaN
            return
        w, r = T[key]
        if val > r:
            flag('reject', f'{label} {val} > {r}')
        elif val > w:
            flag('warn', f'{label} {val} > {w}')

    low('face_px_min', 'face width px', m['face_px'])
    low('sharpness_min', 'blur (sharpness)', m['sharpness'])
    low('face_p95_luma_min', 'dark photo (brightest face part, luma)', m['face_p95_luma'])
    high('clipped_pct_max', 'blown highlights %', m['clipped_pct'])
    high('crushed_pct_max', 'crushed shadows %', m['crushed_pct'])
    high('lr_asym_max', 'uneven left/right light', m['lr_asym'])
    high('yaw_offset_max', 'head turned (yaw offset)', m['yaw_offset'])
    return q


def assess(bgr: np.ndarray, zoner: 'fz.FaceZoner') -> Quality:
    """Whole gate: face found? then metrics and verdict."""
    res = zoner.detect(bgr)
    if res is None:
        return Quality({}, 'reject', ['reject: no face found'])
    return judge(measure(bgr, res.points), res.n_faces)
