import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:cosmetix/core/face/face_coordinate_transform.dart';
import 'package:cosmetix/core/face/face_geometry.dart';
import 'package:cosmetix/core/face/face_points.dart';
import 'package:cosmetix/features/virtual_makeup/domain/face_geometry.dart'
    as legacy;

import '../../photo_check/synthetic_face.dart';

FaceGeometry faceAt(Offset c, double w, {Size size = const Size(720, 1280)}) =>
    FaceGeometry(FacePoints(meshAt(c, w)), imageSize: size);

void main() {
  group('FaceCoordinateTransform', () {
    const sizes = [Size(1280, 720), Size(720, 1280), Size(640, 480)];
    const previews = [
      Size(390, 844),
      Size(375, 667),
      Size(440, 956),
      Size(800, 600),
    ];

    test('toImage(toPreview(p)) == p for every rotation, mirror and fit', () {
      final rnd = math.Random(7);
      for (final img in sizes) {
        for (final pv in previews) {
          for (final rot in [0, 90, 180, 270]) {
            for (final mirror in [false, true]) {
              for (final fit in FaceFit.values) {
                final t = FaceCoordinateTransform(
                  imageSize: img,
                  previewSize: pv,
                  rotationDegrees: rot,
                  mirror: mirror,
                  fit: fit,
                );
                for (var i = 0; i < 20; i++) {
                  final p = Offset(
                    rnd.nextDouble() * img.width,
                    rnd.nextDouble() * img.height,
                  );
                  final back = t.toImage(t.toPreview(p));
                  expect(
                    (back - p).distance,
                    lessThan(1e-6),
                    reason: '$img $pv rot=$rot mirror=$mirror $fit',
                  );
                }
              }
            }
          }
        }
      }
    });

    test('a clockwise quarter turn puts the top-left corner top-right', () {
      const t = FaceCoordinateTransform(
        imageSize: Size(200, 100),
        previewSize: Size(100, 200), // exactly the rotated frame: scale 1
        rotationDegrees: 90,
      );
      expect(t.toPreview(Offset.zero), const Offset(100, 0));
      expect(t.toPreview(const Offset(200, 100)), const Offset(0, 200));
    });

    test('mirror flips left and right of the preview', () {
      const t = FaceCoordinateTransform(
        imageSize: Size(100, 100),
        previewSize: Size(100, 100),
        mirror: true,
      );
      expect(t.toPreview(const Offset(10, 30)), const Offset(90, 30));
    });

    test('cover fills the preview (crops), contain fits inside (bars)', () {
      Rect frame(FaceFit fit) {
        final t = FaceCoordinateTransform(
          imageSize: const Size(720, 1280),
          previewSize: const Size(390, 844),
          fit: fit,
        );
        return Rect.fromPoints(
          t.toPreview(Offset.zero),
          t.toPreview(const Offset(720, 1280)),
        );
      }

      final cover = frame(FaceFit.cover), contain = frame(FaceFit.contain);
      expect(cover.height, closeTo(844, 1e-6));
      expect(cover.width, greaterThan(390)); // cropped at the sides
      expect(contain.width, closeTo(390, 1e-6));
      expect(contain.height, lessThan(844)); // bars at top and bottom
      expect(contain.center.dy, closeTo(422, 1e-6));
    });

    test('the transform applies to a whole face', () {
      final face = faceAt(const Offset(360, 640), 300);
      const t = FaceCoordinateTransform(
        imageSize: Size(720, 1280),
        previewSize: Size(360, 640),
      );
      final m = face.mapped(t.toPreview, const Size(360, 640));
      expect(m.faceWidth, closeTo(150, 0.5));
      expect(
        (m.center - const Offset(180, 320)).distance,
        lessThan(face.bounds.height * 0.5 * 0.5),
      );
      expect(m.widthShare, closeTo(face.widthShare, 1e-9));
    });
  });

  group('FaceGeometry', () {
    test('size, centre and share of the frame', () {
      final g = faceAt(const Offset(360, 640), 360);
      expect(g.faceWidth, closeTo(360, 0.5));
      expect(g.widthShare, closeTo(0.5, 0.001));
      expect(g.bounds.contains(g.noseTip), isTrue);
      expect(
        g.bounds.inflate(1).contains(g.chin),
        isTrue,
      ); // 152 is on the oval edge
      // the chin is below the nose, the nose below the eyes
      expect(g.chin.dy, greaterThan(g.noseTip.dy));
      expect(g.noseTip.dy, greaterThan(g.eyeLeft.first.dy));
    });

    test('a frontal mean face is level and not turned', () {
      final g = faceAt(const Offset(300, 400), 300);
      expect(g.rollDegrees.abs(), lessThan(2));
      expect(g.yawRatio, closeTo(1, 0.1));
      expect(g.pitchDegrees, isNull, reason: 'no 3D pose: pitch is unknown');
      expect(g.yawDegrees, isNull);
    });

    test('the 3D pose wins over the 2D estimate when it is known', () {
      final g = FaceGeometry(
        FacePoints(meshAt(const Offset(300, 400), 300)),
        imageSize: const Size(600, 800),
        pose: const FacePose(yawDegrees: 20, pitchDegrees: -5, rollDegrees: 3),
      );
      expect(g.yawDegrees, 20);
      expect(g.pitchDegrees, -5);
      expect(g.rollDegrees, 3);
    });

    test('a rotated picture rolls the head by the same angle', () {
      final base = meshAt(const Offset(300, 300), 300);
      const a = 15 * math.pi / 180;
      final turned = [
        for (final p in base)
          Offset(
            300 + (p.dx - 300) * math.cos(a) - (p.dy - 300) * math.sin(a),
            300 + (p.dx - 300) * math.sin(a) + (p.dy - 300) * math.cos(a),
          ),
      ];
      final g = FaceGeometry(
        FacePoints(turned),
        imageSize: const Size(600, 600),
      );
      expect(g.rollDegrees, closeTo(15, 1.5));
    });

    test('the try-on still sees the same FacePoints type (re-export)', () {
      final p = legacy.FacePoints(meshAt(const Offset(100, 100), 100));
      expect(p, isA<FacePoints>());
      expect(legacy.FaceIndices.meshSize, FaceIndices.meshSize);
    });
  });
}
