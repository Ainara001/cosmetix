import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:cosmetix/core/face/capture_guidance.dart';
import 'package:cosmetix/core/face/face_geometry.dart';
import 'package:cosmetix/core/face/face_points.dart';

import '../../photo_check/synthetic_face.dart';

const preview = Size(390, 844);
final oval = CaptureThresholds.ovalFor(preview);

/// The mean face with its bounding box centred at [at] (default: the oval
/// centre), [fill] of the oval width wide, turned by [nose] and rolled by
/// [rollDeg].
FaceGeometry face({
  Offset? at,
  double fill = 0.85,
  double nose = 0,
  double rollDeg = 0,
  FacePose? pose,
}) {
  final w = oval.width * fill;
  var pts = meshAt(Offset.zero, w, nose: nose);
  // meshAt moves point 4; the yaw ratio reads the nose tip (point 1)
  pts[FaceIndices.noseTip] += Offset(nose * w, 0);
  final b = FaceGeometry(FacePoints(pts), imageSize: preview).center;
  final target = at ?? oval.center;
  final a = rollDeg * math.pi / 180;
  pts = [
    for (final p in pts)
      Offset(
        target.dx + (p.dx - b.dx) * math.cos(a) - (p.dy - b.dy) * math.sin(a),
        target.dy + (p.dx - b.dx) * math.sin(a) + (p.dy - b.dy) * math.cos(a),
      ),
  ];
  return FaceGeometry(FacePoints(pts), imageSize: preview, pose: pose);
}

CaptureHint eval(FaceGeometry? f, {double? luma = 180, double? motion}) =>
    CaptureGuidance.evaluate(
      CaptureFrame(face: f, oval: oval, faceLuma: luma),
      motion: motion,
    );

void main() {
  test('the guide oval sits in the upper middle of the preview', () {
    expect(oval.center.dx, closeTo(preview.width / 2, 1e-9));
    expect(oval.center.dy, lessThan(preview.height / 2));
    expect(oval.height, greaterThan(oval.width));
    expect(
      Rect.fromLTWH(0, 0, preview.width, preview.height).contains(oval.topLeft),
      isTrue,
    );
  });

  group('one frame', () {
    test('a well placed, frontal, lit, still face is ready', () {
      expect(eval(face(), motion: 0.001), CaptureHint.ready);
    });

    test('no face', () => expect(eval(null), CaptureHint.noFace));

    test('off centre, to the side or up', () {
      expect(
        eval(face(at: oval.center + Offset(oval.width * 0.3, 0))),
        CaptureHint.moveToCenter,
      );
      expect(
        eval(face(at: oval.center - Offset(0, oval.height * 0.3))),
        CaptureHint.moveToCenter,
      );
    });

    test('too far and too close', () {
      expect(eval(face(fill: 0.5)), CaptureHint.moveCloser);
      expect(eval(face(fill: 1.2)), CaptureHint.moveBack);
    });

    test('a turned head: by the nose position, or by the 3D pose', () {
      expect(eval(face(nose: 0.12)), CaptureHint.lookStraight);
      expect(
        eval(
          face(
            pose: const FacePose(
              yawDegrees: -20,
              pitchDegrees: 0,
              rollDegrees: 0,
            ),
          ),
        ),
        CaptureHint.lookStraight,
      );
      expect(
        eval(
          face(
            pose: const FacePose(
              yawDegrees: 3,
              pitchDegrees: 25,
              rollDegrees: 0,
            ),
          ),
        ),
        CaptureHint.lookStraight,
        reason: 'looking down or up',
      );
      expect(
        eval(
          face(
            pose: const FacePose(
              yawDegrees: 5,
              pitchDegrees: -6,
              rollDegrees: 2,
            ),
          ),
          motion: 0,
        ),
        CaptureHint.ready,
      );
    });

    test('a tilted head, either way', () {
      expect(eval(face(rollDeg: 14)), CaptureHint.levelHead);
      expect(eval(face(rollDeg: -14)), CaptureHint.levelHead);
      expect(eval(face(rollDeg: 4), motion: 0), CaptureHint.ready);
    });

    test('too dark, with the same limit as the photo check', () {
      expect(
        eval(face(), luma: CaptureThresholds.minFaceLuma - 1),
        CaptureHint.addLight,
      );
      expect(
        eval(face(), luma: null, motion: 0),
        CaptureHint.ready,
        reason: 'not measured is not dark',
      );
    });

    test('moving', () {
      expect(eval(face(), motion: 0.05), CaptureHint.holdStill);
    });

    test('framing comes first: a far, dark, moving face hears "closer"', () {
      expect(
        eval(face(fill: 0.5), luma: 40, motion: 0.1),
        CaptureHint.moveCloser,
      );
    });
  });

  group('the steady hint', () {
    CaptureFrame frame(FaceGeometry? f, {double luma = 180}) =>
        CaptureFrame(face: f, oval: oval, faceLuma: luma);

    test('"ready" appears only after a steady run of good frames', () {
      final g = CaptureGuidance();
      final f = face();
      final seen = [for (var i = 0; i < 8; i++) g.update(frame(f))];
      // frame 1 has no motion yet; ready needs readyFrames in a row
      expect(
        seen.take(CaptureThresholds.readyFrames - 1),
        everyElement(isNot(CaptureHint.ready)),
      );
      expect(seen.last, CaptureHint.ready);
      expect(g.ready, isTrue);
    });

    test('one bad frame does not make the hint flicker', () {
      final g = CaptureGuidance();
      final f = face();
      for (var i = 0; i < 10; i++) {
        g.update(frame(f));
      }
      expect(g.hint, CaptureHint.ready);
      g.update(frame(face(fill: 0.5))); // one glitch
      expect(g.hint, CaptureHint.ready);
      g.update(frame(f));
      expect(g.hint, CaptureHint.ready);
    });

    test('a lasting change is shown after a few frames', () {
      final g = CaptureGuidance();
      final f = face();
      for (var i = 0; i < 10; i++) {
        g.update(frame(f));
      }
      final far = face(fill: 0.5);
      for (var i = 0; i < CaptureThresholds.switchFrames; i++) {
        g.update(frame(far));
      }
      expect(g.hint, CaptureHint.moveCloser);
    });

    test('a lost face is reported at once, and tracking restarts', () {
      final g = CaptureGuidance();
      final f = face();
      for (var i = 0; i < 10; i++) {
        g.update(frame(f));
      }
      expect(g.update(frame(null)), CaptureHint.noFace);
      expect(g.ready, isFalse);
    });

    test('a face that jumps between frames is asked to hold still', () {
      final g = CaptureGuidance();
      for (var i = 0; i < 10; i++) {
        final shift = Offset(i.isEven ? -8 : 8, 0);
        g.update(frame(face(at: oval.center + shift)));
      }
      expect(g.hint, CaptureHint.holdStill);
    });
  });
}
