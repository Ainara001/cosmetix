import 'dart:typed_data';
import 'dart:ui' show Offset, Size;

import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';

import 'face_geometry.dart';
import 'face_points.dart';

/// The one MediaPipe face-mesh adapter for still pictures. The photo check
/// (`MediaPipePhotoFaceFinder`) and the virtual try-on
/// (`MediaPipeLandmarkProvider`) are thin wrappers over it, so both see the
/// same mesh for the same picture. The live camera uses
/// `FaceStreamEngine`, the same models with tracking turned on.
///
/// BlazeFace (detector) and FaceMesh V2 (478 points) are Apache-2.0 models
/// shipped inside `mediapipe_face_mesh` (docs/mediapipe-models-license-audit.md).
/// They run on the phone: nothing leaves it.
class MediaPipeFaceEngine {
  MediaPipeFaceEngine({this.maxFaces = 4, this.withPose = false});

  final int maxFaces;

  /// Also run the 3D head-pose fit (one extra native call per face).
  final bool withPose;

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
      // one still picture: no tracking, no smoothing across frames
      enableLandmarkTracking: false,
      landmarkSmoothing: null,
    );
  }

  /// Every face of an RGBA picture (empty when there is none), in pixel
  /// coordinates of that picture. Never guesses a face.
  Future<List<FaceGeometry>> detect(
    Uint8List rgba,
    int width,
    int height,
  ) async {
    final pipeline = await _ready();
    final result = pipeline.processMultiFace(
      FaceMeshImage(pixels: rgba, width: width, height: height),
      maxMeshFaces: maxFaces,
    );
    final size = Size(width.toDouble(), height.toDouble());
    return [
      for (final face in result.faces)
        if (face.mesh.landmarks.length >= FaceIndices.meshSize)
          geometryOf(face.mesh, size, withPose: withPose),
    ];
  }

  /// [mesh] (normalised landmarks) as a [FaceGeometry] in pixels of [size].
  static FaceGeometry geometryOf(
    FaceMeshResult mesh,
    Size size, {
    bool withPose = false,
  }) => FaceGeometry(
    FacePoints([
      for (final p in mesh.landmarks)
        Offset(p.x * size.width, p.y * size.height),
    ]),
    imageSize: size,
    pose: withPose ? poseOf(mesh) : null,
  );

  /// MediaPipe's 3D head pose, or null when the fit fails: no pose is better
  /// than a wrong one.
  static FacePose? poseOf(FaceMeshResult mesh) {
    try {
      final p = mesh.estimateGeometry().headPose;
      return FacePose(
        yawDegrees: p.yawDegrees,
        pitchDegrees: p.pitchDegrees,
        rollDegrees: p.rollDegrees,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose() async {
    _detector?.close();
    _mesh?.close();
    _detector = null;
    _mesh = null;
    _pipeline = null;
  }
}
