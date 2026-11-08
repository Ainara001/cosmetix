# Smart Face Capture and the shared face geometry

Stage 4 of the spec. Status: implemented and covered by unit and widget tests;
**not yet run on a physical iPhone** (see "To check on the device").

## Parts

| File | What it does |
|---|---|
| `lib/core/face/face_points.dart` | The 478-point mesh (`FacePoints`) and the index sets (`FaceIndices`). |
| `lib/core/face/face_geometry.dart` | `FaceGeometry`: parts of the face, bounds, share of the frame, roll / yaw / pitch (3D pose when known; pitch is `null` without it, never guessed). |
| `lib/core/face/face_coordinate_transform.dart` | Picture ↔ preview: rotation 0/90/180/270, front-camera mirror, `cover` / `contain`. |
| `lib/core/face/mediapipe_face_engine.dart` | The one MediaPipe adapter for still pictures. The photo check and the try-on wrap it. |
| `lib/core/face/face_stream_engine.dart` | The same models for the live camera: MediaPipe landmark tracking + official One Euro smoothing, in a worker isolate; frames are dropped while one is processed. |
| `lib/core/face/capture_guidance.dart` | Pure Dart: one frame → one hint; anti-flicker (a new hint must hold 3 frames, "ready" 6). All thresholds are named constants in `CaptureThresholds`. |
| `lib/screens/beauty/smart_capture_screen.dart` | The camera screen: dimmed outside + oval (white → green), hint text, optional mesh points, shutter always enabled, gallery button, debug FPS / ms overlay (debug builds only). |

The photo step (`BeautyPhotoScreen`) opens the smart camera for "Сделать фото"
on iOS. The photo it returns goes through the same path as before: the local
photo check, the consent and age gates, then (only if allowed) the AI.
No camera (the simulator) → the system camera picker; no permission → an
explanation and the gallery.

## Hints, in order of priority

1. no face → «Поместите лицо в овал»
2. centre more than 14% of the oval off → «Расположите лицо по центру»
3. face width < 68% / > 102% of the oval → «Поднесите телефон ближе» / «Немного отодвиньте телефон»
4. |yaw| > 12° or |pitch| > 15° (3D pose); without the pose, nose ratio outside 0.72–1.39 → «Посмотрите прямо в камеру»
5. |roll| > 8° → «Держите голову ровно»
6. brightest 5% of the mid-face luma < 110 (the photo check's warning) → «Добавьте освещения»
7. mean landmark movement > 1.2% of the face width per frame → «Не двигайтесь»
8. otherwise → «Можно сделать фото»

The hints only help: they never block the shutter, and the full photo check
runs again on the photo that was taken. Several faces are not checked live
(the stream follows one face); the photo check rejects such a photo.

## Privacy

Frames live in memory, are analysed on the phone and are never written or
sent. `lib/core/face` has no network, file or database code. The photo is
written by the camera plugin to the temporary folder and deleted by the photo
step when it is no longer needed (as before).

## To check on the device

These are the assumptions that only a physical iPhone can confirm:

- frames from `camera_avfoundation` are upright portrait BGRA and mirrored
  like the front preview (so `mirrored = false`, rotation 0). If the mesh
  points are flipped or sideways on the device, fix `DeviceCaptureCamera.mirrored`
  / pass `rotationDegrees` — the transform already supports both;
- the thresholds above feel right in normal use (they are guide values);
- performance.

**How to measure performance** (debug numbers are not release numbers):

1. `flutter run --profile -d <iPhone>`; the debug overlay is off in profile, so
   use DevTools → Performance (UI / raster frame times) and the log.
2. Xcode → Product → Profile → *Time Profiler* (CPU of the worker isolate),
   *Allocations* (memory over 2 minutes of capture: must stay flat),
   *Energy Log* and `ProcessInfo.thermalState` (heat after 2–3 minutes).
3. Record: inference FPS, ms per frame, preview FPS, memory, thermal state,
   for an iPhone SE-class and a Pro-class device.

No performance figures are claimed until this is done; numbers from the
simulator or Android do not count.
