import 'dart:math' as math;
import 'dart:ui' show Offset;

/// Indices of the 478-point MediaPipe face mesh that the zones use. The index
/// lists are the canonical MediaPipe sets (FACEMESH_LIPS, eyes, brows, oval).
class FaceIndices {
  FaceIndices._();

  static const meshSize = 478;

  static const lipsOuter = [
    61, 146, 91, 181, 84, 17, 314, 405, 321, 375, //
    291, 409, 270, 269, 267, 0, 37, 39, 40, 185,
  ];
  static const lipsInner = [
    78, 95, 88, 178, 87, 14, 317, 402, 318, 324, //
    308, 415, 310, 311, 312, 13, 82, 81, 80, 191,
  ];

  /// The open eye of the person's right eye (left in the picture) and left eye.
  static const eyeRight = [
    33, 7, 163, 144, 145, 153, 154, 155, 133, //
    173, 157, 158, 159, 160, 161, 246,
  ];
  static const eyeLeft = [
    362, 382, 381, 380, 374, 373, 390, 249, 263, //
    466, 388, 387, 386, 385, 384, 398,
  ];

  /// Upper lash line, outer corner to inner corner.
  static const lashRight = [33, 246, 161, 160, 159, 158, 157, 173, 133];
  static const lashLeft = [263, 466, 388, 387, 386, 385, 384, 398, 362];

  /// Lower edge of the brow, outer to inner.
  static const browLowerRight = [70, 63, 105, 66, 107];
  static const browLowerLeft = [300, 293, 334, 296, 336];

  /// Both edges of each brow as a closed ring (used to keep brows out of
  /// the skin area).
  static const browRingRight = [70, 63, 105, 66, 107, 55, 65, 52, 53, 46];
  static const browRingLeft = [
    300,
    293,
    334,
    296,
    336,
    285,
    295,
    282,
    283,
    276,
  ];

  static const faceOval = [
    10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379, //
    378, 400, 377, 152, 148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 127,
    162, 21, 54, 103, 67, 109,
  ];

  static const faceEdgeRight = 234;
  static const faceEdgeLeft = 454;
  static const eyeOuterRight = 33;
  static const eyeOuterLeft = 263;
  static const mouthCornerRight = 61;
  static const mouthCornerLeft = 291;
  static const noseTip = 1;
}

/// The face mesh of one photo in PIXEL coordinates of that photo.
class FacePoints {
  FacePoints(List<Offset> points)
    : assert(points.length >= FaceIndices.meshSize),
      points = List.unmodifiable(points);

  /// Builds the points from normalised (0..1) coordinates.
  factory FacePoints.fromNormalized(
    List<({double x, double y})> normalized,
    int imageWidth,
    int imageHeight,
  ) => FacePoints([
    for (final p in normalized) Offset(p.x * imageWidth, p.y * imageHeight),
  ]);

  final List<Offset> points;

  Offset operator [](int i) => points[i];

  List<Offset> pick(List<int> indices) => [for (final i in indices) points[i]];

  /// Distance between the two cheek edges of the face oval.
  double get faceWidth =>
      (points[FaceIndices.faceEdgeRight] - points[FaceIndices.faceEdgeLeft])
          .distance;

  /// Head roll in degrees: the angle of the line between the outer eye corners.
  double get rollDegrees {
    final a = points[FaceIndices.eyeOuterRight];
    final b = points[FaceIndices.eyeOuterLeft];
    return math.atan2(b.dy - a.dy, b.dx - a.dx) * 180 / math.pi;
  }

  /// How far the nose is from the middle between the face edges: 1 = frontal;
  /// below about 0.65 or above about 1.5 the head is clearly turned.
  double get yawRatio {
    final nose = points[FaceIndices.noseTip].dx;
    final left = points[FaceIndices.faceEdgeRight].dx;
    final right = points[FaceIndices.faceEdgeLeft].dx;
    final toLeft = (nose - left).abs();
    final toRight = (right - nose).abs();
    if (toRight < 1e-6) return 99;
    return toLeft / toRight;
  }
}
