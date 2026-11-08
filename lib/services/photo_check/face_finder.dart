import 'dart:ui' show Offset;

import 'package:cosmetix/core/face/mediapipe_face_engine.dart';

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

/// The photo check's face finder: a thin wrapper over the shared
/// [MediaPipeFaceEngine] (BlazeFace + FaceMesh V2, on the phone: the photo does
/// not leave it).
class MediaPipePhotoFaceFinder implements PhotoFaceFinder {
  MediaPipePhotoFaceFinder({int maxFaces = 5})
    : _engine = MediaPipeFaceEngine(maxFaces: maxFaces);

  final MediaPipeFaceEngine _engine;

  @override
  Future<List<List<Offset>>> find(PhotoPixels photo) async => [
    for (final face in await _engine.detect(
      photo.rgba,
      photo.width,
      photo.height,
    ))
      face.points.points,
  ];

  @override
  Future<void> dispose() => _engine.dispose();
}
