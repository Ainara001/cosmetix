import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:cosmetix/core/face/face_geometry.dart';
import 'package:cosmetix/core/face/face_points.dart';
import 'package:cosmetix/core/face/face_zones.dart';
import 'package:cosmetix/core/face/mean_mesh.dart';

FaceGeometry geometry(List<Offset> pts) =>
    FaceGeometry(FacePoints(pts), imageSize: const Size(600, 800));

Offset mean(List<Offset> p) => p.reduce((a, b) => a + b) / p.length.toDouble();

void main() {
  final face = geometry(meanFace(const Offset(300, 380), 320));
  final zones = FaceZones.of(face);

  test(
    'every zone has an area, is visible on a frontal face, and a label point inside it',
    () {
      for (final z in FaceZone.values) {
        expect(zones.area(z), greaterThan(0), reason: '$z');
        expect(zones.visible(z), isTrue, reason: '$z');
        expect(zones.zoneAt(zones.labelPoint(z)), z, reason: '$z label');
      }
      // the cheeks of a frontal face are about the same size
      final r =
          zones.area(FaceZone.cheekLeft) / zones.area(FaceZone.cheekRight);
      expect(r, closeTo(1, 0.25));
    },
  );

  test('eyes, brows and lips are never skin', () {
    for (final part in [
      face.eyeLeft,
      face.eyeRight,
      face.browLeft,
      face.browRight,
      face.lips,
    ]) {
      expect(zones.isSkin(mean(part)), isFalse);
      for (final p in part) {
        expect(zones.zoneAt(p), isNull, reason: 'outline point $p');
      }
    }
  });

  test('the zones do not overlap (a dense grid over the face)', () {
    final b = face.bounds;
    var skin = 0;
    for (var j = 0; j <= 80; j++) {
      for (var i = 0; i <= 80; i++) {
        final p = Offset(b.left + b.width * i / 80, b.top + b.height * j / 80);
        if (zones.inHole(p)) continue;
        final inside = [
          for (final z in FaceZone.values)
            if (FaceZones.of(face).polygon(z).isNotEmpty &&
                _inside(zones.polygon(z), p))
              z,
        ];
        expect(inside.length, lessThanOrEqualTo(1), reason: '$p in $inside');
        if (inside.isNotEmpty) skin++;
      }
    }
    expect(
      skin,
      greaterThan(500),
      reason: 'the zones cover a good part of the face',
    );
  });

  test(
    'the forehead is above the brows, the chin below the lips, the nose between the cheeks',
    () {
      final brows = mean([...face.browLeft, ...face.browRight]).dy;
      expect(zones.labelPoint(FaceZone.forehead).dy, lessThan(brows));
      expect(
        zones.labelPoint(FaceZone.chin).dy,
        greaterThan(mean(face.lips).dy),
      );
      final nose = zones.labelPoint(FaceZone.nose).dx;
      // the person's right cheek is on the LEFT of a non-mirrored picture
      expect(zones.labelPoint(FaceZone.cheekRight).dx, lessThan(nose));
      expect(zones.labelPoint(FaceZone.cheekLeft).dx, greaterThan(nose));
    },
  );

  test('zones follow the face: scaled, moved and rotated', () {
    const a = 20 * math.pi / 180;
    final base = meanFace(const Offset(0, 0), 320);
    final turned = geometry([
      for (final p in base)
        Offset(
          150 + 0.6 * (p.dx * math.cos(a) - p.dy * math.sin(a)),
          500 + 0.6 * (p.dx * math.sin(a) + p.dy * math.cos(a)),
        ),
    ]);
    final z2 = FaceZones.of(turned);
    for (final z in FaceZone.values) {
      expect(z2.area(z) / zones.area(z), closeTo(0.36, 0.01), reason: '$z');
      expect(z2.zoneAt(z2.labelPoint(z)), z);
    }
    expect(z2.isSkin(mean(turned.eyeLeft)), isFalse);
  });

  test('a cheek turned away from the camera is not usable', () {
    // squeeze the person's left side (image right) to a third: a turned head
    final pts = [
      for (final p in meanFace(const Offset(300, 380), 320))
        p.dx > 300 ? Offset(300 + (p.dx - 300) * 0.3, p.dy) : p,
    ];
    final z = FaceZones.of(geometry(pts));
    expect(z.visible(FaceZone.cheekLeft), isFalse);
    expect(z.visible(FaceZone.cheekRight), isTrue);
  });

  test('the codes round-trip', () {
    for (final z in FaceZone.values) {
      expect(FaceZone.fromCode(z.code), z);
    }
    expect(FaceZone.fromCode('ear'), isNull);
  });
}

bool _inside(List<Offset> poly, Offset p) {
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i], b = poly[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) &&
        p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}
