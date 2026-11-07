"""Face zones (forehead, cheeks, nose, chin) from MediaPipe Face Landmarker.

The detector gives 478 landmarks per face. This module turns them into five
zone polygons. Every zone is an ORDERED loop of landmark indices (not a convex
hull: a cheek is not convex once the nose and the mouth are cut out).

Left/right are the SUBJECT's left/right. In the photo the subject's right
cheek is on the image's left.

Only indices that were checked by eye on the photos in tools/eval/data are
used. Zones are masks for measuring colour/texture, not a diagnosis.
"""
from __future__ import annotations

import os
from dataclasses import dataclass

import cv2
import numpy as np

MODEL_URL = ('https://storage.googleapis.com/mediapipe-models/face_landmarker/'
             'face_landmarker/float16/1/face_landmarker.task')
DEFAULT_MODEL = os.path.join(os.path.dirname(__file__), 'models', 'face_landmarker.task')

# --- subject's RIGHT side (image left). The left side is mirrored below. ---
_R = {
    # under the eye -> outer -> down to the mouth-corner level -> along the
    # nasolabial fold back up. The face contour (234, 93, 132, 58...) is
    # deliberately not used: it hits ears/hair.
    'cheek': [116, 117, 118, 119, 100, 126, 209, 203, 206, 216, 212, 214,
              135, 172, 58, 132, 93],
}

# Mirror pairs (right index -> left index), obtained from frontal photos by
# reflecting the normalized mesh about its midline and taking the nearest
# landmark (see tools/eval/README.md). Midline points map to themselves.
MIRROR = {
    116: 345, 117: 346, 118: 347, 119: 348, 100: 329, 126: 355, 209: 429,
    203: 423, 206: 426, 216: 436, 212: 432, 214: 434, 138: 367, 215: 435,
    213: 433, 147: 376, 123: 352, 135: 364, 172: 397, 58: 288, 132: 361, 93: 323,
    193: 417, 122: 351, 196: 419, 174: 399, 217: 437, 198: 420, 49: 279,
    64: 294, 98: 327, 97: 326, 2: 2,
    32: 262, 194: 418, 83: 313, 18: 18, 176: 400, 148: 377, 152: 152,
    54: 284, 103: 332, 67: 297, 109: 338, 10: 10, 21: 251, 70: 300, 63: 283,
    105: 334, 66: 296, 107: 336, 9: 9,
}

# Standard MediaPipe outlines used to cut non-skin holes.
LIPS_OUTER = [61, 146, 91, 181, 84, 17, 314, 405, 321, 375, 291, 409, 270,
              269, 267, 0, 37, 39, 40, 185]
EYE_RIGHT = [33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158, 159, 160, 161, 246]
EYE_LEFT = [263, 249, 390, 373, 374, 380, 381, 382, 362, 398, 384, 385, 386, 387, 388, 466]
FACE_OVAL = [10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379,
             378, 400, 377, 152, 148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 127,
             162, 21, 54, 103, 67, 109]

ZONE_LOOPS = {
    'forehead': [54, 103, 67, 109, 10, 338, 297, 332, 284, 300, 293, 334, 296, 336,
                 9, 107, 66, 105, 63, 70, 21],
    'nose': [193, 122, 196, 174, 217, 198, 209, 49, 64, 98, 97, 2, 326, 327, 294,
             279, 429, 420, 437, 399, 419, 351, 417],
    'chin': [32, 194, 83, 18, 313, 418, 262, 400, 377, 152, 148, 176],
    'cheek_right': _R['cheek'],
    'cheek_left': [MIRROR[i] for i in _R['cheek']],
}
ZONE_NAMES = list(ZONE_LOOPS)
# BGR colours for overlays
ZONE_COLORS = {'forehead': (0, 200, 255), 'cheek_right': (0, 220, 0), 'cheek_left': (255, 160, 0),
               'nose': (255, 0, 255), 'chin': (0, 0, 255)}

# how much to shrink each zone away from its edge, as a fraction of the face width
ERODE_FRAC = 0.012
MAX_FACES = 5   # more are not counted; the group-photo rule only needs 'more than one'


@dataclass
class FaceResult:
    points: np.ndarray       # (478, 3): x, y in pixels, z in pixels (relative depth)
    n_faces: int
    inference_ms: float
    other_widths: tuple = ()  # widths (px) of the other faces found, 234-454 distance


class FaceZoner:
    """Wraps MediaPipe Face Landmarker (loads the model once)."""

    def __init__(self, model_path: str = DEFAULT_MODEL):
        import mediapipe as mp
        from mediapipe.tasks import python as mpt
        from mediapipe.tasks.python import vision
        if not os.path.exists(model_path):
            raise FileNotFoundError(f'{model_path} missing; download {MODEL_URL}')
        self._mp = mp
        self._lm = vision.FaceLandmarker.create_from_options(
            vision.FaceLandmarkerOptions(base_options=mpt.BaseOptions(model_asset_path=model_path),
                                         num_faces=MAX_FACES))

    def detect(self, bgr: np.ndarray) -> FaceResult | None:
        import time
        h, w = bgr.shape[:2]
        rgb = np.ascontiguousarray(cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB))
        image = self._mp.Image(image_format=self._mp.ImageFormat.SRGB, data=rgb)
        t = time.perf_counter()
        res = self._lm.detect(image)
        ms = (time.perf_counter() - t) * 1000
        if not res.face_landmarks:
            return None
        faces = [np.array([[p.x * w, p.y * h, p.z * w] for p in f]) for f in res.face_landmarks]
        # the detector's order is arbitrary: analyse the LARGEST face
        pts = max(faces, key=lambda f: np.ptp(f[:, 0]) * np.ptp(f[:, 1]))
        others = tuple(float(np.linalg.norm(f[454, :2] - f[234, :2])) for f in faces if f is not pts)
        return FaceResult(pts, len(faces), ms, others)


def zone_polygons(points: np.ndarray) -> dict[str, np.ndarray]:
    return {name: points[idx, :2].astype(np.float32) for name, idx in ZONE_LOOPS.items()}


def _fill(shape, poly) -> np.ndarray:
    m = np.zeros(shape[:2], np.uint8)
    cv2.fillPoly(m, [np.round(poly).astype(np.int32)], 255)
    return m


def zone_masks(points: np.ndarray, shape, erode_frac: float = ERODE_FRAC) -> dict[str, np.ndarray]:
    """Binary uint8 masks per zone, with eyes and lips cut out and edges eroded."""
    face_w = float(np.linalg.norm(points[454, :2] - points[234, :2]))
    k = max(1, int(round(erode_frac * face_w)))
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * k + 1, 2 * k + 1))
    holes = np.zeros(shape[:2], np.uint8)
    for loop in (LIPS_OUTER, EYE_RIGHT, EYE_LEFT):
        holes |= _fill(shape, points[loop, :2])
    holes = cv2.dilate(holes, kernel)
    out = {}
    for name, poly in zone_polygons(points).items():
        m = _fill(shape, poly)
        m = cv2.erode(m, kernel)
        m[holes > 0] = 0
        out[name] = m
    return out


def head_pose(points: np.ndarray) -> dict[str, float]:
    """Rough head pose from the mesh, no solver.

    roll_deg: tilt of the line through the outer eye corners (in-plane rotation).
    yaw_offset: |nose tip position between the two cheek edges - 0.5| measured
    ALONG the eye line, so a tilted but frontal head is not read as turned
    (0 = frontal, grows as the head turns; a profile is about 0.5).
    """
    eye = points[263, :2] - points[33, :2]
    roll = float(np.degrees(np.arctan2(eye[1], eye[0])))
    u = eye / np.linalg.norm(eye)
    width = float((points[454, :2] - points[234, :2]) @ u)
    ratio = float((points[4, :2] - points[234, :2]) @ u) / width
    return {'yaw_offset': float(abs(ratio - 0.5)), 'roll_deg': roll}


def face_mask(points: np.ndarray, shape) -> np.ndarray:
    return _fill(shape, points[FACE_OVAL, :2])


def draw_overlay(bgr: np.ndarray, points: np.ndarray, masks: dict[str, np.ndarray]) -> np.ndarray:
    vis = bgr.copy()
    layer = bgr.copy()
    for name, m in masks.items():
        layer[m > 0] = ZONE_COLORS[name]
    vis = cv2.addWeighted(layer, 0.35, vis, 0.65, 0)
    for name, m in masks.items():
        cs, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        cv2.drawContours(vis, cs, -1, ZONE_COLORS[name], max(1, bgr.shape[1] // 400))
    return vis
