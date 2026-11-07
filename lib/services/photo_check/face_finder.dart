import 'dart:ui' show Offset;

import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';

import 'package:cosmetix/services/photo_check/photo_pixels.dart';

/// Finds the faces in a photo, on the phone. Each face is its 478 landmark
/// points in PIXEL coordinates of the photo. The photo check only knows this
/// interface; tests use a fake and the app uses [MediaPipePhotoFaceFinder].
abstract interface class PhotoFaceFinder {
  /// Every face found (empty when there is none). Never guesses a face.
  Future<List<List<Offset>>> find(PhotoPixels photo);

  /// Frees the native resources.
  Future<void> dispose();
}

/// BlazeFace (detector) and FaceMesh V2 (478 points) from the `mediapipe_face_mesh`
/// package that the app already contains (Apache 2.0 models, see
/// docs/mediapipe-models-license-audit.md). They run on the phone: the photo does not
/// leave it. This file is its own small adapter; it does not use the virtual try-on code.
class MediaPipePhotoFaceFinder implements PhotoFaceFinder {
  MediaPipePhotoFaceFinder({this.maxFaces = 5});

  final int maxFaces;
  FaceDetectorProcessor? _detector;
  FaceMeshProcessor? _mesh;
  FaceMeshInferencePipeline? _pipeline;

  Future<FaceMeshInferencePipeline> _ready() async {
    final existing = _pipeline;
    if (existing != null) return existing;
    final detector = await FaceDetectorProcessor.create(maxResults: maxFaces);
    final mesh = await FaceMeshProcessor.create();
    _detector = detector;
    _mesh = mesh;
    return _pipeline = FaceMeshInferencePipeline(
      detector: detector,
      mesh: mesh,
      enableLandmarkTracking:
          false, // one still photo: no tracking, no smoothing
      landmarkSmoothing: null,
    );
  }

  @override
  Future<List<List<Offset>>> find(PhotoPixels photo) async {
    final pipeline = await _ready();
    final frame = FaceMeshImage(
      pixels: photo.rgba,
      width: photo.width,
      height: photo.height,
    );
    final result = pipeline.processMultiFace(frame, maxMeshFaces: maxFaces);
    return [
      for (final face in result.faces)
        if (face.mesh.landmarks.length >= 478)
          [
            for (final p in face.mesh.landmarks)
              Offset(p.x * photo.width, p.y * photo.height),
          ],
    ];
  }

  @override
  Future<void> dispose() async {
    _detector?.close();
    _mesh?.close();
    _detector = null;
    _mesh = null;
    _pipeline = null;
  }
}
