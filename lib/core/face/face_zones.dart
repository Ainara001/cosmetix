import 'dart:ui' show Offset, Path, PathOperation, Rect;

import 'face_geometry.dart';
import 'face_points.dart';

/// The five skin zones of a face. Left / right are the PERSON's: their right
/// cheek is on the left of a non-mirrored photo.
enum FaceZone {
  forehead('forehead', 'Лоб'),
  cheekRight('cheek_right', 'Правая щека'),
  cheekLeft('cheek_left', 'Левая щека'),
  nose('nose', 'Нос'),
  chin('chin', 'Подбородок');

  const FaceZone(this.code, this.label);
  final String code;
  final String label;

  static FaceZone? fromCode(String? c) {
    for (final z in values) {
      if (z.code == c) return z;
    }
    return null;
  }
}

/// Face zones from the 478-point mesh, in the coordinates of the given
/// [FaceGeometry] (photo, preview or the schematic face alike).
///
/// The zone loops are the ones of the photo check and of the reference
/// `tools/eval/face_zones.py` (checked by eye on the evaluation photos): one
/// zone system for skin measurements, photo comparison and the try-on. As in
/// the reference, the face contour is not used (it hits ears and hair) and the
/// top of the forehead stops at the top of the mesh. Unlike the reference loop
/// alone, the eyes, the BROWS (the forehead loop runs along their lower edge)
/// and the lips are cut out, with a margin, so a zone is skin only.
///
/// Hair falling on the forehead, glasses or a hand are not detected from the
/// mesh: the person confirms what they see. Zones are areas to look at, not a
/// diagnosis.
class FaceZones {
  FaceZones.of(this.face)
    : _margin = face.faceWidth * marginShare,
      _holes = [for (final loop in holeLoops) face.points.pick(loop)];

  final FaceGeometry face;
  final double _margin;
  final List<List<Offset>> _holes;

  /// Holes grow by this share of the face width (the photo check's erosion).
  static const marginShare = 0.012;

  /// A cheek whose area is below this share of the other cheek's is turned
  /// away from the camera: not usable on this picture.
  static const minCheekRatio = 0.45;

  static const loops = <FaceZone, List<int>>{
    FaceZone.forehead: [
      54, 103, 67, 109, 10, 338, 297, 332, 284, 300, 293, 334, 296, 336, //
      9, 107, 66, 105, 63, 70, 21,
    ],
    FaceZone.nose: [
      193, 122, 196, 174, 217, 198, 209, 49, 64, 98, 97, 2, 326, 327, 294, //
      279, 429, 420, 437, 399, 419, 351, 417,
    ],
    FaceZone.chin: [32, 194, 83, 18, 313, 418, 262, 400, 377, 152, 148, 176],
    FaceZone.cheekRight: [
      116, 117, 118, 119, 100, 126, 209, 203, 206, 216, 212, 214, 135, 172, //
      58, 132, 93,
    ],
    FaceZone.cheekLeft: [
      345, 346, 347, 348, 329, 355, 429, 423, 426, 436, 432, 434, 364, 397, //
      288, 361, 323,
    ],
  };

  /// Not skin: eyes, brows, lips.
  static const holeLoops = [
    FaceIndices.eyeRight,
    FaceIndices.eyeLeft,
    FaceIndices.browRingRight,
    FaceIndices.browRingLeft,
    FaceIndices.lipsOuter,
  ];

  List<Offset> polygon(FaceZone z) => face.points.pick(loops[z]!);

  /// Area of the zone loop (holes not subtracted), in square units.
  double area(FaceZone z) => _area(polygon(z));

  /// False when the zone cannot be judged on this picture: a cheek turned
  /// away (much smaller than the other one).
  bool visible(FaceZone z) {
    if (z == FaceZone.cheekLeft || z == FaceZone.cheekRight) {
      final other = z == FaceZone.cheekLeft
          ? FaceZone.cheekRight
          : FaceZone.cheekLeft;
      final a = area(z), b = area(other);
      return b <= 0 || a / b >= minCheekRatio;
    }
    return area(z) > 0;
  }

  /// Not skin: inside or within the margin of an eye, brow or lips.
  bool inHole(Offset p) {
    for (final h in _holes) {
      if (_contains(h, p) || _distance(h, p) <= _margin) return true;
    }
    return false;
  }

  /// The zone at [p], or null outside every zone or on an eye, brow or lips.
  FaceZone? zoneAt(Offset p) {
    if (inHole(p)) return null;
    for (final z in FaceZone.values) {
      if (_contains(polygon(z), p)) return z;
    }
    return null;
  }

  /// Is [p] skin of a zone?
  bool isSkin(Offset p) => zoneAt(p) != null;

  /// The zone as a path with the holes cut out, for drawing.
  Path path(FaceZone z) {
    // Cut holes with a real difference: even-odd filling would paint a hole
    // that lies partly outside the zone (lips next to a cheek, brows below
    // the forehead edge).
    var p = Path()..addPolygon(polygon(z), true);
    final b = _bounds(polygon(z));
    for (final h in _holes) {
      if (_bounds(h).overlaps(b)) {
        p = Path.combine(
          PathOperation.difference,
          p,
          Path()..addPolygon(h, true),
        );
      }
    }
    return p;
  }

  /// A point well inside the zone (for a label): the mean of the loop,
  /// moved to the nearest skin sample if it falls in a hole.
  Offset labelPoint(FaceZone z) {
    final poly = polygon(z);
    var c = Offset.zero;
    for (final p in poly) {
      c += p;
    }
    c = c / poly.length.toDouble();
    if (zoneAt(c) == z) return c;
    final b = _bounds(poly);
    Offset? best;
    var bestD = double.infinity;
    for (var j = 1; j < 12; j++) {
      for (var i = 1; i < 12; i++) {
        final q = Offset(b.left + b.width * i / 12, b.top + b.height * j / 12);
        final d = (q - c).distanceSquared;
        if (d < bestD && zoneAt(q) == z) {
          best = q;
          bestD = d;
        }
      }
    }
    return best ?? c;
  }

  static double _area(List<Offset> p) {
    var s = 0.0;
    for (var i = 0; i < p.length; i++) {
      final a = p[i], b = p[(i + 1) % p.length];
      s += a.dx * b.dy - b.dx * a.dy;
    }
    return (s / 2).abs();
  }

  static Rect _bounds(List<Offset> p) {
    var l = p.first.dx, r = l, t = p.first.dy, b = t;
    for (final q in p) {
      if (q.dx < l) l = q.dx;
      if (q.dx > r) r = q.dx;
      if (q.dy < t) t = q.dy;
      if (q.dy > b) b = q.dy;
    }
    return Rect.fromLTRB(l, t, r, b);
  }

  /// Even-odd point in polygon (the loops are not convex).
  static bool _contains(List<Offset> poly, Offset p) {
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

  /// Distance from [p] to the outline of [poly].
  static double _distance(List<Offset> poly, Offset p) {
    var best = double.infinity;
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i], b = poly[(i + 1) % poly.length];
      final ab = b - a;
      final len2 = ab.distanceSquared;
      final t = len2 == 0
          ? 0.0
          : (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
      final d = (p - (a + ab * t)).distance;
      if (d < best) best = d;
    }
    return best;
  }
}
