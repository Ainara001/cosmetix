"""Photo quality gate (OpenCV): is this selfie good enough to analyse?

Metrics are computed on the FACE, not the whole frame, so a sharp background
cannot hide a blurry face:

  face_px         face width in pixels (too small = no detail)
  sharpness       variance of the Laplacian of the face crop, rescaled to a fixed
                  face width so the number does not depend on the photo size
  skin_L_mean     mean CIELAB L* (0-100) over the skin zones (reported only: it
                  depends on the person's skin tone, so it is not used to judge)
  skin_chroma     median CIELAB chroma sqrt(a*a+b*b) over the skin zones: ~0 means a black-and-white
                  photo, where tone, undertone and colour type cannot be judged at all.
                  (Rule added AFTER the hold-out run showed 3 grayscale photos passing the gate.)
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
    'skin_chroma_min': (3.0, 2.0),
    'clipped_pct_max': (4.0, 12.0),
    'crushed_pct_max': (25.0, 50.0),
    'lr_asym_max': (0.35, float('inf')),   # side light: warn only, never reject
    'yaw_offset_max': (0.15, 0.25),
    # second face: any other face is a warning, one at least a quarter as wide as the main one rejects
    'second_face_ratio_max': (0.0, 0.25),
    # opaque dark lenses: eyes darker than the cheeks (below 0.8) AND flat (contrast below 0.07).
    # Open eyes keep a contrast of at least 0.10 on the 76 development photos (the only real pair
    # of dark glasses among them: 0.037); closed eyelids are as bright as the cheeks (about 1.0).
    # Chosen on the development photos and synthetic lenses, never on the evaluation set.
    'eyes_covered': (0.8, 0.07),
    # share of the cheeks/forehead/nose that is the colour of this face's skin; warn only: a beard,
    # hair or a deep shadow lowers it and a bearded face is a valid photo
    'skin_visible_min': (0.5, None),
}


@dataclass
class Quality:
    metrics: dict = field(default_factory=dict)
    verdict: str = 'ok'              # ok | warn | reject
    reasons: list = field(default_factory=list)


SKIN_DELTA_E = 20.0     # a zone pixel counts as "skin of this face" within this CIELAB distance


def eye_cover(luma: np.ndarray, masks: dict, points: np.ndarray) -> tuple[float, float]:
    """(darkness, contrast) of the eye openings relative to the cheeks.

    darkness = median luma inside the eye polygons / median luma of the cheeks;
    contrast = std of luma inside them / the same cheek median. Dark lenses give a
    LOW darkness and a LOW contrast (uniform dark); open eyes (even dark irises on
    dark skin) keep both higher. Relative to the person's own cheeks, so a dark skin
    tone does not look like a cover."""
    eyes = np.zeros(luma.shape, np.uint8)
    for loop in (fz.EYE_RIGHT, fz.EYE_LEFT):
        cv2.fillPoly(eyes, [np.round(points[loop, :2]).astype(np.int32)], 255)
    cheeks = (masks['cheek_left'] > 0) | (masks['cheek_right'] > 0)
    if eyes.sum() == 0 or cheeks.sum() < 50:
        return float('nan'), float('nan')
    ref = max(1.0, float(np.median(luma[cheeks])))
    e = luma[eyes > 0].astype(np.float32)
    return float(np.median(e)) / ref, float(e.std()) / ref


def visible_skin(lab: np.ndarray, masks: dict) -> float:
    """Share of the cheek, forehead and nose zones that is the colour of THIS face's skin.

    Reference = the median CIELAB colour of those zones; a pixel counts when it is within
    SKIN_DELTA_E of it. A mask, a scarf, heavy hair or a big shadow lowers it. It cannot see
    a hand (same colour as the face) and it also lowers for beards over the cheeks."""
    z = (masks['cheek_left'] > 0) | (masks['cheek_right'] > 0) | (masks['forehead'] > 0) | (masks['nose'] > 0)
    if z.sum() < 100:
        return float('nan')
    px = np.stack([lab[:, :, 0][z] * (100.0 / 255.0), lab[:, :, 1][z] - 128.0, lab[:, :, 2][z] - 128.0], 1)
    ref = np.median(px, 0)
    return float((np.linalg.norm(px - ref, axis=1) <= SKIN_DELTA_E).mean())


def measure(bgr: np.ndarray, points: np.ndarray, masks: dict | None = None,
            other_widths: tuple = ()) -> dict:
    """masks: pass the result of fz.zone_masks if you already have it (saves a recompute)."""
    if masks is None:
        masks = fz.zone_masks(points, bgr.shape)
    skin = np.zeros(bgr.shape[:2], np.uint8)
    for m in masks.values():
        skin |= m
    face_w = float(np.linalg.norm(points[454, :2] - points[234, :2]))
    # sharpness: face bbox crop, rescaled so the face is NORM_FACE_W wide
    x0, y0 = np.floor(points[fz.FACE_OVAL, :2].min(0)).astype(int)
    x1, y1 = np.ceil(points[fz.FACE_OVAL, :2].max(0)).astype(int)
    x0, y0 = max(0, x0), max(0, y0)
    x1, y1 = min(bgr.shape[1], x1), min(bgr.shape[0], y1)
    if x1 - x0 < 8 or y1 - y0 < 8:      # face (almost) outside the frame
        sharp = 0.0
    else:
        crop = cv2.cvtColor(bgr[y0:y1, x0:x1], cv2.COLOR_BGR2GRAY)
        s = NORM_FACE_W / face_w
        crop = cv2.resize(crop, None, fx=s, fy=s, interpolation=cv2.INTER_AREA if s < 1 else cv2.INTER_CUBIC)
        sharp = float(cv2.Laplacian(crop, cv2.CV_64F).var())
    lab = cv2.cvtColor(bgr, cv2.COLOR_BGR2LAB).astype(np.float32)
    L = lab[:, :, 0] * (100.0 / 255.0)
    luma = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    sk = skin > 0
    lab_ab = lab[:, :, 1:][sk] - 128.0
    n = max(1, int(sk.sum()))
    cl, cr = masks['cheek_left'] > 0, masks['cheek_right'] > 0
    lr = np.nan
    if cl.sum() > 50 and cr.sum() > 50:
        a, b = float(L[cl].mean()), float(L[cr].mean())
        lr = abs(a - b) / max(1e-6, (a + b) / 2)
    pose = fz.head_pose(points)
    dark, contrast = eye_cover(luma, masks, points)
    return {
        'second_face_ratio': round(max(other_widths) / face_w, 3) if other_widths else 0.0,
        'eye_dark_ratio': round(dark, 3) if dark == dark else float('nan'),
        'eye_contrast': round(contrast, 3) if contrast == contrast else float('nan'),
        'skin_visible': round(visible_skin(lab, masks), 3),
        'face_px': round(face_w, 1),
        'sharpness': round(sharp, 1),
        'skin_L_mean': round(float(L[sk].mean()), 1) if sk.any() else float('nan'),
        'skin_chroma': round(float(np.median(np.hypot(lab_ab[:, 0], lab_ab[:, 1]))), 2) if sk.any() else float('nan'),
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

    if n_faces > 1 and 'second_face_ratio' not in m:    # metrics without face widths: just warn
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

    ratio = m.get('second_face_ratio', 0.0)
    if ratio >= T['second_face_ratio_max'][1]:
        flag('reject', f'another face in the frame ({ratio:.2f} of the main face width)')
    elif ratio > T['second_face_ratio_max'][0]:
        flag('warn', f'a smaller face in the background ({ratio:.2f} of the main face width)')
    dark, flat = m.get('eye_dark_ratio', float('nan')), m.get('eye_contrast', float('nan'))
    if dark == dark and flat == flat and dark < T['eyes_covered'][0] and flat < T['eyes_covered'][1]:
        flag('reject', f'eyes look covered by dark lenses (darkness {dark:.2f}, contrast {flat:.2f})')
    vis = m.get('skin_visible', float('nan'))
    if vis == vis and vis < T['skin_visible_min'][0]:
        flag('warn', f'little visible skin: {vis:.2f} of the cheeks, forehead and nose')
    low('face_px_min', 'face width px', m['face_px'])
    low('sharpness_min', 'blur (sharpness)', m['sharpness'])
    low('skin_chroma_min', 'grayscale photo (skin colour chroma)', m['skin_chroma'])
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
    return judge(measure(bgr, res.points, None, res.other_widths), res.n_faces)
