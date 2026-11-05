import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../domain/face_geometry.dart';
import 'polygon_raster.dart';

/// Soft masks of the zones, one per product plus the visible skin of the face.
/// Every mask is 0..1; 0 means "do not touch this pixel".
class ZoneMasks {
  const ZoneMasks({
    required this.lips,
    required this.eyeshadow,
    required this.blush,
    required this.skin,
  });

  final MaskPatch lips;
  final MaskPatch eyeshadow;
  final MaskPatch blush;

  /// The face oval without eyes, lips and brows (where blush may go, and the
  /// area the blemish suggestion looks at).
  final MaskPatch skin;
}

class ZoneMaskBuilder {
  ZoneMaskBuilder._();

  /// How far the eyeshadow reaches from the lash line toward the brow.
  static const eyeshadowReach = 0.7;

  static ZoneMasks build(FacePoints face, int width, int height) {
    final fw = face.faceWidth;
    final skin = _skin(face, width, height, fw);
    return ZoneMasks(
      lips: _lips(face, width, height, fw),
      eyeshadow: _eyeshadow(face, width, height, fw),
      blush: _blush(face, width, height, fw, skin),
      skin: skin,
    );
  }

  static MaskPatch _empty() => MaskPatch(0, 0, 0, 0);

  static MaskPatch _lips(FacePoints f, int w, int h, double fw) {
    final outer = f.pick(FaceIndices.lipsOuter);
    final b = PolygonRaster.boundsOf(outer, w, h, margin: 4);
    if (b == null) return _empty();
    final o = PolygonRaster.fill(outer, b.x0, b.y0, b.w, b.h);
    final i = PolygonRaster.fill(
      f.pick(FaceIndices.lipsInner),
      b.x0,
      b.y0,
      b.w,
      b.h,
    );
    for (var k = 0; k < o.data.length; k++) {
      o.data[k] = math.max(0, o.data[k] - i.data[k]);
    }
    PolygonRaster.blur(o, math.max(1, 0.004 * fw));
    return o;
  }

  /// The point at fraction [u] (0..1) along a polyline.
  static Offset _pointAlong(List<Offset> line, double u) {
    final pos = u * (line.length - 1);
    final i = pos.floor().clamp(0, line.length - 2);
    return Offset.lerp(line[i], line[i + 1], pos - i)!;
  }

  static MaskPatch _eyeshadow(FacePoints f, int w, int h, double fw) {
    final eyes = <({List<Offset> lash, List<Offset> brow, List<Offset> open})>[
      (
        lash: f.pick(FaceIndices.lashRight),
        brow: f.pick(FaceIndices.browLowerRight),
        open: f.pick(FaceIndices.eyeRight),
      ),
      (
        lash: f.pick(FaceIndices.lashLeft),
        brow: f.pick(FaceIndices.browLowerLeft),
        open: f.pick(FaceIndices.eyeLeft),
      ),
    ];
    final all = [
      for (final e in eyes) ...[...e.lash, ...e.brow],
    ];
    final b = PolygonRaster.boundsOf(all, w, h, margin: 6);
    if (b == null) return _empty();
    final out = MaskPatch(b.x0, b.y0, b.w, b.h);
    const scales = [0.3, 0.55, eyeshadowReach];
    for (final e in eyes) {
      for (final s in scales) {
        final top = <Offset>[];
        for (var i = 0; i < e.lash.length; i++) {
          final brow = _pointAlong(e.brow, i / (e.lash.length - 1));
          top.add(Offset.lerp(e.lash[i], brow, s)!);
        }
        final poly = [...e.lash, ...top.reversed];
        final band = PolygonRaster.fill(poly, b.x0, b.y0, b.w, b.h);
        for (var k = 0; k < out.data.length; k++) {
          out.data[k] += band.data[k] / scales.length;
        }
      }
      final open = PolygonRaster.fill(e.open, b.x0, b.y0, b.w, b.h);
      for (var k = 0; k < out.data.length; k++) {
        out.data[k] = math.max(0, out.data[k] - open.data[k]);
      }
    }
    PolygonRaster.blur(out, math.max(1, 0.012 * fw));
    return out;
  }

  static MaskPatch _skin(FacePoints f, int w, int h, double fw) {
    final oval = f.pick(FaceIndices.faceOval);
    final b = PolygonRaster.boundsOf(oval, w, h);
    if (b == null) return _empty();
    final skin = PolygonRaster.fill(oval, b.x0, b.y0, b.w, b.h);
    for (final hole in [
      f.pick(FaceIndices.eyeRight),
      f.pick(FaceIndices.eyeLeft),
      f.pick(FaceIndices.lipsOuter),
      f.pick(FaceIndices.browRingRight),
      f.pick(FaceIndices.browRingLeft),
    ]) {
      final p = PolygonRaster.fill(hole, b.x0, b.y0, b.w, b.h);
      for (var k = 0; k < skin.data.length; k++) {
        skin.data[k] = math.max(0, skin.data[k] - p.data[k]);
      }
    }
    return skin;
  }

  /// The middle of the cheek: halfway between the outer eye corner and the
  /// mouth corner, pulled a little toward the ear.
  static Offset cheekCenter(FacePoints f, {required bool right}) {
    final eye = f[right ? FaceIndices.eyeOuterRight : FaceIndices.eyeOuterLeft];
    final mouth =
        f[right ? FaceIndices.mouthCornerRight : FaceIndices.mouthCornerLeft];
    final ear = f[right ? FaceIndices.faceEdgeRight : FaceIndices.faceEdgeLeft];
    return Offset.lerp(Offset.lerp(eye, mouth, 0.5)!, ear, 0.15)!;
  }

  static MaskPatch _blush(
    FacePoints f,
    int w,
    int h,
    double fw,
    MaskPatch skin,
  ) {
    final r = 0.13 * fw;
    final centers = [cheekCenter(f, right: true), cheekCenter(f, right: false)];
    final pts = [
      for (final c in centers) ...[c - Offset(r, r), c + Offset(r, r)],
    ];
    final b = PolygonRaster.boundsOf(pts, w, h);
    if (b == null) return _empty();
    final out = MaskPatch(b.x0, b.y0, b.w, b.h);
    for (var y = 0; y < b.h; y++) {
      for (var x = 0; x < b.w; x++) {
        var v = 0.0;
        for (final c in centers) {
          final dx = (b.x0 + x + 0.5 - c.dx) / r;
          final dy = (b.y0 + y + 0.5 - c.dy) / (r * 0.8);
          final d = math.sqrt(dx * dx + dy * dy);
          if (d < 1) {
            final t = 1 - d;
            v = math.max(v, t * t * (3 - 2 * t)); // smoothstep falloff
          }
        }
        // only on visible skin: no blush on the background, eyes or lips
        out.data[y * b.w + x] = v * skin.at(b.x0 + x, b.y0 + y);
      }
    }
    return out;
  }
}
