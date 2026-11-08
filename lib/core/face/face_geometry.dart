import 'dart:ui' show Offset, Rect, Size;

import 'face_points.dart';

/// Head orientation in degrees from MediaPipe's 3D fit. The package does not
/// document the sign of each angle, so callers compare magnitudes only.
class FacePose {
  const FacePose({
    required this.yawDegrees,
    required this.pitchDegrees,
    required this.rollDegrees,
  });

  /// Left/right turn.
  final double yawDegrees;

  /// Up/down nod.
  final double pitchDegrees;

  /// In-plane tilt.
  final double rollDegrees;
}

/// The geometry of ONE face, shared by the photo check, the smart camera, the
/// face zones and the virtual try-on: the mesh in pixel coordinates of
/// [imageSize], its main parts, where it sits in the frame and how the head is
/// turned.
///
/// [pose] is MediaPipe's 3D estimate when it was computed. Without it only
/// the 2D measures are known: roll (eye line) and [yawRatio]; pitch is then
/// unknown (null) rather than guessed.
class FaceGeometry {
  const FaceGeometry(this.points, {required this.imageSize, this.pose});

  final FacePoints points;
  final Size imageSize;
  final FacePose? pose;

  List<Offset> get oval => points.pick(FaceIndices.faceOval);
  List<Offset> get eyeLeft => points.pick(FaceIndices.eyeLeft);
  List<Offset> get eyeRight => points.pick(FaceIndices.eyeRight);
  List<Offset> get lips => points.pick(FaceIndices.lipsOuter);
  List<Offset> get browLeft => points.pick(FaceIndices.browRingLeft);
  List<Offset> get browRight => points.pick(FaceIndices.browRingRight);
  Offset get noseTip => points[FaceIndices.noseTip];

  /// The chin tip (mesh point 152), not "the lowest point": with a tilted
  /// head the lowest oval point is somewhere on the jaw.
  Offset get chin => points[FaceIndices.chin];

  /// Bounding box of the face oval.
  Rect get bounds {
    final o = oval;
    var minX = o.first.dx, maxX = minX, minY = o.first.dy, maxY = minY;
    for (final p in o) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  Offset get center => bounds.center;

  /// Face width (cheek edge to cheek edge) in pixels.
  double get faceWidth => points.faceWidth;

  /// Face width as a share of the frame width: 0.5 = half the picture.
  double get widthShare =>
      imageSize.width <= 0 ? 0 : faceWidth / imageSize.width;

  /// Roll from the 3D pose when known, else from the eye line.
  double get rollDegrees => pose?.rollDegrees ?? points.rollDegrees;

  /// Yaw from the 3D pose, null without it (use [yawRatio] then).
  double? get yawDegrees => pose?.yawDegrees;

  /// Pitch from the 3D pose; null without it: there is no honest 2D pitch.
  double? get pitchDegrees => pose?.pitchDegrees;

  /// Nose position between the face edges: 1 = frontal (see [FacePoints]).
  double get yawRatio => points.yawRatio;

  /// The same face in another coordinate system (e.g. a camera preview).
  FaceGeometry mapped(Offset Function(Offset) map, Size size) => FaceGeometry(
    FacePoints([for (final p in points.points) map(p)]),
    imageSize: size,
    pose: pose,
  );
}
