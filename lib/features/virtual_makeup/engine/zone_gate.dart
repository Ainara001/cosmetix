import 'dart:math' as math;
import 'dart:typed_data';

import 'color_math.dart';
import 'makeup_backend.dart';
import 'pigment_params.dart';
import 'polygon_raster.dart';
import '../domain/makeup_look.dart';

/// What the pigment engine learns about one zone of one photo (once, then
/// cached): the average colour of the zone in linear light, and for every pixel
/// of the zone a COLOUR GATE, how much the pixel looks like the zone.
///
/// The gate keeps paint off things that are not the zone but lie under its mask:
/// a finger or a nail at the mouth, teeth, hair, a glasses frame. A pixel whose
/// colour is far from the typical colour of the zone (in "typical spreads", with
/// lightness counting little: a shadow or a highlight on the lips is still the
/// lips) gets fading paint, and none when it is far enough. The gate is a MASK:
/// it is spread over a few pixels so that neighbours are not treated abruptly,
/// the photo itself is never changed.
class ZoneGate {
  const ZoneGate(this.gate, this.ref);

  /// 0..1 per pixel of the zone's patch.
  final Float32List gate;

  /// Average colour of the zone, linear RGB, weighted by mask and gate.
  final List<double> ref;

  static ZoneGate of(
    PreparedFace face,
    MakeupZone zone,
    MaskPatch patch,
    PigmentParams params,
  ) {
    final key = 'pigment:${zone.name}';
    final cached = face.cache[key];
    if (cached is ZoneGate) return cached;
    return face.cache[key] = _build(
      face,
      patch,
      params,
      params.chromaFloorOf(zone),
    );
  }

  static ZoneGate _build(
    PreparedFace face,
    MaskPatch patch,
    PigmentParams params,
    double chromaFloor,
  ) {
    final src = face.image;
    final n = patch.width * patch.height;
    final l = Float32List(n), a = Float32List(n), b = Float32List(n);
    final lin = List.generate(3, (_) => Float32List(n));
    final core = <int>[]; // pixels that surely belong to the zone
    for (var py = 0; py < patch.height; py++) {
      for (var px = 0; px < patch.width; px++) {
        final i = py * patch.width + px;
        if (patch.data[i] <= 0) continue;
        final o = ((patch.y0 + py) * src.width + patch.x0 + px) * 4;
        final c = ColorMath.rgbToLab(
          src.pixels[o],
          src.pixels[o + 1],
          src.pixels[o + 2],
        );
        l[i] = c.l;
        a[i] = c.a;
        b[i] = c.b;
        for (var ch = 0; ch < 3; ch++) {
          lin[ch][i] = ColorMath.srgbByteToLinear(src.pixels[o + ch]);
        }
        if (patch.data[i] >= 0.5) core.add(i);
      }
    }
    final gate = Float32List(n);
    if (core.length < 20) {
      for (var i = 0; i < n; i++) {
        gate[i] = patch.data[i] > 0 ? 1 : 0;
      }
    } else {
      final medL = _median([for (final i in core) l[i]]);
      final medA = _median([for (final i in core) a[i]]);
      final medB = _median([for (final i in core) b[i]]);
      // typical spread (median absolute deviation, scaled), with floors so a
      // very even zone does not reject its own natural variation
      double spread(Float32List v, double med, double floor) => math.max(
        floor,
        1.4826 * _median([for (final i in core) (v[i] - med).abs()]),
      );
      final sL = spread(l, medL, 8), sA = spread(a, medA, chromaFloor);
      final sB = spread(b, medB, chromaFloor);
      final wl = params.lightnessWeight;
      for (var i = 0; i < n; i++) {
        if (patch.data[i] <= 0) continue;
        // the colour of a very dark pixel is noise: judge it by lightness
        final trust = _ease(
          params.chromaReliableStart,
          params.chromaReliableEnd,
          l[i],
        );
        final dl = (l[i] - medL) / sL;
        final da = trust * (a[i] - medA) / sA;
        final db = trust * (b[i] - medB) / sB;
        final d = math.sqrt(wl * dl * dl + da * da + db * db);
        gate[i] = 1 - _ease(params.gateStart, params.gateEnd, d);
      }
    }
    // spread the gate a little, so neighbouring pixels are not treated abruptly
    final soft = params.gateSoftness * face.points.faceWidth;
    if (core.length >= 20 && soft >= 1) {
      final g = MaskPatch(patch.x0, patch.y0, patch.width, patch.height);
      g.data.setAll(0, gate);
      PolygonRaster.blur(g, soft);
      for (var i = 0; i < n; i++) {
        gate[i] = patch.data[i] > 0 ? g.data[i] : 0;
      }
    }
    // the average colour of the zone in linear light, weighted by mask and gate
    final ref = [0.0, 0.0, 0.0];
    var wsum = 0.0;
    for (var i = 0; i < n; i++) {
      final w = patch.data[i] * gate[i];
      if (w <= 0) continue;
      wsum += w;
      for (var ch = 0; ch < 3; ch++) {
        ref[ch] += w * lin[ch][i];
      }
    }
    for (var ch = 0; ch < 3; ch++) {
      ref[ch] = math.max(1e-4, wsum > 0 ? ref[ch] / wsum : 0.2);
    }
    return ZoneGate(gate, ref);
  }

  static double _median(List<double> v) {
    if (v.isEmpty) return 0;
    final s = [...v]..sort();
    return s[s.length ~/ 2];
  }

  static double _ease(double e0, double e1, double x) {
    final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }
}
