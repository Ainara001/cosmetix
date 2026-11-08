import 'dart:ui' show Offset, Rect, Size;

import 'package:cosmetix/services/photo_check/photo_rules.dart';

import 'face_geometry.dart';
import 'face_points.dart';

/// What the smart camera tells the person, one thing at a time, in this
/// order of priority.
enum CaptureHint {
  noFace,
  moveToCenter,
  moveCloser,
  moveBack,
  lookStraight,
  levelHead,
  addLight,
  holdStill,
  ready,
}

/// One analysed camera frame. [face] is in PREVIEW coordinates (already
/// passed through `FaceCoordinateTransform`), so it can be compared with the
/// oval drawn on screen.
class CaptureFrame {
  const CaptureFrame({required this.face, required this.oval, this.faceLuma});

  final FaceGeometry? face;

  /// The face guide on screen, in the same preview coordinates.
  final Rect oval;

  /// Brightest 5% of the face skin, 0..255 (BT.601 luma, like the photo
  /// check); null when it was not measured on this frame.
  final double? faceLuma;
}

/// The thresholds of the smart camera. They are GUIDE values for framing, not
/// the photo check: the photo is checked again, fully, after it is taken.
class CaptureThresholds {
  CaptureThresholds._();

  /// Where the guide oval sits in the preview: its width as a share of the
  /// preview width, its height as a multiple of its width, and its centre as
  /// a share of the preview height (a little above the middle, where a face
  /// naturally is when the phone is held at eye level).
  static const ovalWidthShare = 0.70;
  static const ovalAspect = 1.32;
  static const ovalCenterY = 0.44;

  /// The face centre may be this far from the oval centre (share of the oval
  /// width / height) and still count as centred.
  static const centerTolerance = 0.14;

  /// Face width (cheek edge to cheek edge) relative to the oval width.
  static const minFill = 0.68, maxFill = 1.02;

  /// Head turn. With the 3D pose: degrees. Without it: the nose position
  /// ratio of `FacePoints.yawRatio` (1 = frontal).
  static const maxYawDegrees = 12.0;
  static const maxPitchDegrees = 15.0;
  static const yawRatioBand = (0.72, 1.39);
  static const maxRollDegrees = 8.0;

  /// The same "too dark" warning as the photo check.
  static double get minFaceLuma => PhotoThresholds.faceP95LumaMin.$1;

  /// Mean landmark movement between frames, as a share of the face width,
  /// above which the face is "moving".
  static const maxMotion = 0.012;

  /// A new hint is shown after it holds this many frames in a row (no
  /// flicker); "ready" needs a longer steady run.
  static const switchFrames = 3;
  static const readyFrames = 6;

  /// The guide oval for a preview of [size].
  static Rect ovalFor(Size size) {
    final w = size.width * ovalWidthShare;
    final h = w * ovalAspect;
    return Rect.fromCenter(
      center: Offset(size.width / 2, size.height * ovalCenterY),
      width: w,
      height: h,
    );
  }
}

/// Turns the stream of analysed frames into ONE steady hint. Pure Dart: no
/// camera, no widgets, nothing sent anywhere.
class CaptureGuidance {
  CaptureHint _shown = CaptureHint.noFace;
  CaptureHint _candidate = CaptureHint.noFace;
  int _run = 0;
  List<Offset>? _previous;

  /// The hint on screen now.
  CaptureHint get hint => _shown;
  bool get ready => _shown == CaptureHint.ready;

  /// Feeds the next frame and returns the hint to show.
  CaptureHint update(CaptureFrame frame) {
    final motion = _motion(frame.face);
    final raw = evaluate(frame, motion: motion);
    if (raw == _candidate) {
      _run++;
    } else {
      _candidate = raw;
      _run = 1;
    }
    final need = raw == CaptureHint.ready
        ? CaptureThresholds.readyFrames
        : CaptureThresholds.switchFrames;
    // losing the face is shown at once: there is nothing to hold steady
    if (_run >= need || raw == CaptureHint.noFace) _shown = raw;
    return _shown;
  }

  void reset() {
    _shown = _candidate = CaptureHint.noFace;
    _run = 0;
    _previous = null;
  }

  /// Mean movement of a few stable points since the previous frame, as a
  /// share of the face width; null for the first frame.
  double? _motion(FaceGeometry? face) {
    if (face == null) {
      _previous = null;
      return null;
    }
    final now = face.points.pick(_motionPoints);
    final before = _previous;
    _previous = now;
    if (before == null || face.faceWidth <= 0) return null;
    var sum = 0.0;
    for (var i = 0; i < now.length; i++) {
      sum += (now[i] - before[i]).distance;
    }
    return sum / now.length / face.faceWidth;
  }

  static const _motionPoints = [
    FaceIndices.noseTip,
    FaceIndices.chin,
    FaceIndices.eyeOuterLeft,
    FaceIndices.eyeOuterRight,
    FaceIndices.faceEdgeLeft,
    FaceIndices.faceEdgeRight,
    10, // top of the forehead
  ];

  /// The hint for ONE frame, without the anti-flicker memory.
  static CaptureHint evaluate(CaptureFrame frame, {double? motion}) {
    final face = frame.face;
    if (face == null) return CaptureHint.noFace;
    final oval = frame.oval;
    final c = face.center;
    final dx = (c.dx - oval.center.dx).abs() / oval.width;
    final dy = (c.dy - oval.center.dy).abs() / oval.height;
    if (dx > CaptureThresholds.centerTolerance ||
        dy > CaptureThresholds.centerTolerance) {
      return CaptureHint.moveToCenter;
    }
    final fill = face.faceWidth / oval.width;
    if (fill < CaptureThresholds.minFill) return CaptureHint.moveCloser;
    if (fill > CaptureThresholds.maxFill) return CaptureHint.moveBack;

    final yaw = face.yawDegrees;
    final turned = yaw != null
        ? yaw.abs() > CaptureThresholds.maxYawDegrees
        : face.yawRatio < CaptureThresholds.yawRatioBand.$1 ||
              face.yawRatio > CaptureThresholds.yawRatioBand.$2;
    final pitch = face.pitchDegrees;
    if (turned ||
        (pitch != null && pitch.abs() > CaptureThresholds.maxPitchDegrees)) {
      return CaptureHint.lookStraight;
    }
    if (face.rollDegrees.abs() > CaptureThresholds.maxRollDegrees) {
      return CaptureHint.levelHead;
    }
    final luma = frame.faceLuma;
    if (luma != null && luma < CaptureThresholds.minFaceLuma) {
      return CaptureHint.addLight;
    }
    if (motion != null && motion > CaptureThresholds.maxMotion) {
      return CaptureHint.holdStill;
    }
    return CaptureHint.ready;
  }
}
