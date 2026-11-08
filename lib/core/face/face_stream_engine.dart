import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';

import 'face_geometry.dart';
import 'face_points.dart';
import 'mediapipe_face_engine.dart';

/// The face mesh for a LIVE camera: the same BlazeFace + FaceMesh V2 models as
/// [MediaPipeFaceEngine], with MediaPipe's own landmark tracking (the detector
/// is skipped while the face is followed) and its official One Euro smoothing,
/// in a worker isolate so the preview never waits for the model.
///
/// Frames stay in memory on the phone; nothing here can send them anywhere.
class FaceStreamEngine {
  FaceStreamEngine._(this._pipeline);

  final FaceMeshIsolatePipeline _pipeline;

  static Future<FaceStreamEngine> start() async => FaceStreamEngine._(
    await FaceMeshIsolatePipeline.spawn<Object?>(
      _create,
      null,
      debugName: 'cosmetix-face-stream',
    ),
  );

  static Future<FaceMeshInferencePipeline> _create(Object? _) async =>
      FaceMeshInferencePipeline(
        detector: await FaceDetectorProcessor.create(),
        mesh: await FaceMeshProcessor.create(),
        // defaults: landmark tracking on, official stream-mode smoothing
      );

  /// True while a frame is being processed: the camera loop drops frames
  /// instead of queueing them (a queue would only add latency).
  bool get busy => _pipeline.isBusy || _pipeline.isClosed;

  /// The face of [frame], or null when there is none. Coordinates are pixels
  /// of the frame after [rotationDegrees] (MediaPipe returns the mesh in the
  /// rotated frame).
  Future<FaceGeometry?> process(
    FaceMeshImage frame, {
    int rotationDegrees = 0,
  }) async {
    final result = await _pipeline.process(
      frame,
      rotationDegrees: rotationDegrees,
    );
    final mesh = result.meshResult;
    if (mesh == null || mesh.landmarks.length < FaceIndices.meshSize) {
      return null;
    }
    final size = rotationDegrees % 180 == 0
        ? Size(frame.width.toDouble(), frame.height.toDouble())
        : Size(frame.height.toDouble(), frame.width.toDouble());
    return MediaPipeFaceEngine.geometryOf(mesh, size, withPose: true);
  }

  Future<void> close() => _pipeline.close();

  /// Brightest 5% of the middle of the face (cheeks, nose, lower forehead) in
  /// a BGRA frame, as BT.601 luma 0..255, the measure the photo check judges
  /// darkness by. About 1 600 samples: cheap enough for every frame. Null when
  /// the face box is outside the frame.
  static double? faceLuma(
    Uint8List bgra,
    int bytesPerRow,
    int width,
    int height,
    Rect face,
  ) {
    // the inner part of the face box: no hair, no background, no beard
    final box = Rect.fromLTRB(
      face.left + face.width * 0.2,
      face.top + face.height * 0.25,
      face.right - face.width * 0.2,
      face.bottom - face.height * 0.2,
    ).intersect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
    if (box.width < 2 || box.height < 2) return null;
    const grid = 40;
    final values = <double>[];
    for (var j = 0; j < grid; j++) {
      final y = (box.top + (j + 0.5) * box.height / grid).floor();
      for (var i = 0; i < grid; i++) {
        final x = (box.left + (i + 0.5) * box.width / grid).floor();
        final o = y * bytesPerRow + x * 4;
        if (o + 2 >= bgra.length) continue;
        values.add(0.114 * bgra[o] + 0.587 * bgra[o + 1] + 0.299 * bgra[o + 2]);
      }
    }
    if (values.isEmpty) return null;
    values.sort();
    return values[((values.length - 1) * 0.95).round()];
  }
}
