"""Known image changes used by the stress tests (all BGR uint8 in, BGR uint8 out)."""
import cv2
import numpy as np


def blur(sigma_frac):
    """Gaussian blur with sigma = sigma_frac * face width."""
    return lambda bgr, face_w: cv2.GaussianBlur(bgr, (0, 0), sigma_frac * face_w)


def gamma(g):
    lut = np.array([255 * (i / 255) ** g for i in range(256)], np.uint8)
    return lambda bgr, face_w=None: cv2.LUT(bgr, lut)


def gain(k):
    return lambda bgr, face_w=None: np.clip(bgr.astype(np.float32) * k, 0, 255).astype(np.uint8)


def shrink(target_w):
    def run(bgr, face_w):
        s = target_w / face_w
        return cv2.resize(bgr, None, fx=s, fy=s, interpolation=cv2.INTER_AREA)
    return run


def cast(r, g=1.0, b=1.0):
    """A white-balance error: multiply the red / green / blue channels (cast(1.15, 1, .85) = warmer)."""
    mul = np.array([b, g, r], np.float32)          # BGR order
    return lambda bgr, face_w=None: np.clip(bgr.astype(np.float32) * mul, 0, 255).astype(np.uint8)


def beauty_filter(sat=1.4, warm=(1.08, 1.0, 0.92), smooth=9):
    """A rough 'Instagram-like' filter: skin smoothing + saturation boost + warm tint.
    It is NOT any real app's filter; it only imitates the kind of change filters make."""
    def run(bgr, face_w=None):
        sm = cv2.bilateralFilter(bgr, smooth, 40, 40)
        hsv = cv2.cvtColor(sm, cv2.COLOR_BGR2HSV).astype(np.float32)
        hsv[:, :, 1] = np.clip(hsv[:, :, 1] * sat, 0, 255)
        out = cv2.cvtColor(hsv.astype(np.uint8), cv2.COLOR_HSV2BGR).astype(np.float32)
        out *= np.array([warm[2], warm[1], warm[0]], np.float32)
        return np.clip(out, 0, 255).astype(np.uint8)
    return run


def jpeg_bytes(bgr, quality=80) -> bytes:
    ok, buf = cv2.imencode('.jpg', bgr, [cv2.IMWRITE_JPEG_QUALITY, quality])
    if not ok:
        raise ValueError('JPEG encoding failed')
    return buf.tobytes()
