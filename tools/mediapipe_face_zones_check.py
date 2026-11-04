"""Hands-on check of MediaPipe Face Landmarker (see docs/skin-analysis-research.md).

Does it find a face, how many landmarks, how fast on CPU, and do the zone
polygons land on the right parts. The zone indices below are a ROUGH first
draft (cheeks too small, "chin" covers the whole lower face).

    python3.11 -m venv venv && venv/bin/pip install mediapipe opencv-python-headless
    # model: https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task
    venv/bin/python tools/mediapipe_face_zones_check.py photo.jpg out.png
"""
import time, sys
import numpy as np, cv2
import mediapipe as mp
from mediapipe.tasks import python as mpt
from mediapipe.tasks.python import vision

img_path, out_path = sys.argv[1], sys.argv[2]
bgr = cv2.imread(img_path)
rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
h, w = rgb.shape[:2]
opts = vision.FaceLandmarkerOptions(
    base_options=mpt.BaseOptions(model_asset_path='face_landmarker.task'),
    num_faces=1)
lm = vision.FaceLandmarker.create_from_options(opts)
image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
res = lm.detect(image)
print('image', w, 'x', h)
print('faces found:', len(res.face_landmarks))
pts = res.face_landmarks[0]
print('landmarks per face:', len(pts))
# latency over 30 runs
t = time.perf_counter()
for _ in range(30):
    lm.detect(image)
print('mean latency per photo: %.1f ms (CPU, this Mac)' % ((time.perf_counter() - t) / 30 * 1000))
xy = np.array([[p.x * w, p.y * h] for p in pts])
zones = {
 'forehead': [54,103,67,109,10,338,297,332,284,333,298,301,300,293,334,296,336,9,107,66,105,63,70,156],
 'left_cheek': [116,117,118,119,100,142,203,206,216,207,187,147,123,50,101,36,205],
 'right_cheek': [345,346,347,348,329,371,423,426,436,427,411,376,352,280,330,266,425],
 'nose': [6,197,195,5,4,1,19,94,2,98,97,326,327,168,193,417,122,351,196,419,3,51,45,275,281,248],
 'chin': [152,377,400,378,379,365,397,288,361,323,454,175,171,148,176,149,150,136,172,58,132,93,234,18,200,199,208,428],
}
vis = bgr.copy()
colors = {'forehead':(0,200,255),'left_cheek':(0,255,0),'right_cheek':(255,160,0),'nose':(255,0,255),'chin':(0,0,255)}
for name, idx in zones.items():
    poly = cv2.convexHull(xy[idx].astype(np.int32))
    cv2.polylines(vis, [poly], True, colors[name], 2)
    m = np.zeros((h, w), np.uint8); cv2.fillConvexPoly(m, poly, 255)
    print('zone %-12s pixels=%6d  mean RGB=%s' % (name, int(m.sum()/255), tuple(int(v) for v in rgb[m>0].mean(0))))
cv2.imwrite(out_path, vis)
print('saved', out_path)
