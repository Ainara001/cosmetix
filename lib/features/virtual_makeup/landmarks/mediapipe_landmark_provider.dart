import 'package:cosmetix/core/face/mediapipe_face_engine.dart';

import '../domain/face_geometry.dart';
import '../engine/rgba_image.dart';
import 'face_landmark_provider.dart';

/// The try-on's face mesh: a thin wrapper over the shared
/// [MediaPipeFaceEngine] (BlazeFace + FaceMesh V2, on the phone).
///
/// Not verified on a physical iPhone or an Android phone yet: see
/// docs/real-skin-makeup-plan.md.
class MediaPipeLandmarkProvider implements FaceLandmarkProvider {
  MediaPipeLandmarkProvider({int maxFaces = 4})
    : _engine = MediaPipeFaceEngine(maxFaces: maxFaces);

  final MediaPipeFaceEngine _engine;

  @override
  Future<List<FacePoints>> detect(RgbaImage image) async => [
    for (final face in await _engine.detect(
      image.pixels,
      image.width,
      image.height,
    ))
      face.points,
  ];

  @override
  Future<void> dispose() => _engine.dispose();
}
