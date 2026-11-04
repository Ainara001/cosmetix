import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';

import '../domain/face_geometry.dart';
import '../engine/rgba_image.dart';
import 'face_landmark_provider.dart';

/// Face mesh from the `mediapipe_face_mesh` package: BlazeFace (detector) and
/// FaceMesh V2 (478 points), both Apache-2.0 MediaPipe models that ship inside
/// the package and run on the phone. This is the ONLY file that uses the package.
///
/// Not verified on a physical iPhone or an Android phone yet: see
/// docs/real-skin-makeup-plan.md.
class MediaPipeLandmarkProvider implements FaceLandmarkProvider {
  MediaPipeLandmarkProvider({this.maxFaces = 4});

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
      // one still photo: no tracking, no smoothing across frames
      enableLandmarkTracking: false,
      landmarkSmoothing: null,
    );
  }

  @override
  Future<List<FacePoints>> detect(RgbaImage image) async {
    final pipeline = await _ready();
    final frame = FaceMeshImage(
      pixels: image.pixels,
      width: image.width,
      height: image.height,
    );
    final result = pipeline.processMultiFace(frame, maxMeshFaces: maxFaces);
    return [
      for (final face in result.faces)
        if (face.mesh.landmarks.length >= FaceIndices.meshSize)
          FacePoints.fromNormalized(
            [for (final p in face.mesh.landmarks) (x: p.x, y: p.y)],
            image.width,
            image.height,
          ),
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
