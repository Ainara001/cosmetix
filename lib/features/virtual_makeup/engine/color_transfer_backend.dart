import 'dart:typed_data';

import '../domain/makeup_look.dart';
import 'color_math.dart';
import 'makeup_backend.dart';
import 'polygon_raster.dart';
import 'rgba_image.dart';

/// Stage 1 engine: it moves the colour of each zone toward the chosen colour.
///
/// For every pixel the change is `mask * (1 - protection) * intensity * shift`,
/// where `shift` is THE SAME number for every pixel of the zone (target colour
/// minus the zone's average colour). A shift that is equal everywhere keeps the
/// differences between neighbouring pixels, so the texture of the skin and of
/// the lips (pores, scars, spots, redness variation) stays. No pixel is blurred
/// or replaced; only the soft MASK is blurred.
class ColorTransferBackend implements SyncMakeupBackend {
  const ColorTransferBackend();

  @override
  String get id => 'colour-transfer-v1';

  @override
  BackendCapabilities get capabilities =>
      const BackendCapabilities(supportsReference: false, runsOnDevice: true);

  /// How much of the colour gap a zone closes at intensity 1.
  static const _lightness = {
    MakeupZone.lips: 0.6,
    MakeupZone.eyeshadow: 0.8,
    MakeupZone.blush: 0.4,
  };
  static const _chroma = {
    MakeupZone.lips: 0.95,
    MakeupZone.eyeshadow: 0.9,
    MakeupZone.blush: 0.75,
  };

  /// Below this the change is smaller than one colour level: leave the pixel.
  static const _minEffect = 0.004;

  @override
  Future<RgbaImage> render(MakeupRequest request) async => renderSync(request);

  @override
  RgbaImage renderSync(MakeupRequest request) {
    if (request.reference != null) {
      throw UnsupportedError('$id cannot copy a look from a reference photo');
    }
    final face = request.face;
    final out = face.image.copy();
    final protection = request.protection;
    final w = face.image.width;
    final zones = [
      for (final zone in MakeupZone.values)
        if (request.look.of(zone).active && !face.maskOf(zone).isEmpty) zone,
    ];
    // Where two zones cover the same pixel their shifts ADD UP: the second zone
    // starts from what the first one produced, not from the original photo.
    // (One zone alone never needs this, so the map is only made for several.)
    final touched = zones.length > 1 ? Uint8List(w * face.image.height) : null;
    for (final zone in zones) {
      final look = request.look.of(zone);
      final patch = face.maskOf(zone);
      final lab = _labOf(face, zone, patch);
      final target = ColorMath.colorToLab(look.color);
      final kl = _lightness[zone]!, kc = _chroma[zone]!;
      final dl = (target.l - lab.meanL) * kl;
      final da = (target.a - lab.meanA) * kc;
      final db = (target.b - lab.meanB) * kc;
      for (var py = 0; py < patch.height; py++) {
        final y = patch.y0 + py;
        for (var px = 0; px < patch.width; px++) {
          final m = patch.data[py * patch.width + px];
          if (m <= 0) continue;
          final x = patch.x0 + px;
          var p = m * look.intensity;
          if (protection != null) p *= 1 - protection.at(x, y);
          if (p < _minEffect) continue;
          final i = py * patch.width + px;
          final o = (y * w + x) * 4;
          var l = lab.l[i], a = lab.a[i], b = lab.b[i];
          if (touched != null) {
            if (touched[y * w + x] != 0) {
              final c = ColorMath.rgbToLab(
                out.pixels[o],
                out.pixels[o + 1],
                out.pixels[o + 2],
              );
              l = c.l;
              a = c.a;
              b = c.b;
            }
            touched[y * w + x] = 1;
          }
          ColorMath.labToRgb(l + p * dl, a + p * da, b + p * db, out.pixels, o);
        }
      }
    }
    return out;
  }

  _LabPatch _labOf(PreparedFace face, MakeupZone zone, MaskPatch patch) {
    final key = 'lab:${zone.name}';
    final cached = face.cache[key];
    if (cached is _LabPatch) return cached;
    final n = patch.width * patch.height;
    final l = Float32List(n), a = Float32List(n), b = Float32List(n);
    final src = face.image;
    var sumM = 0.0, sl = 0.0, sa = 0.0, sb = 0.0;
    for (var py = 0; py < patch.height; py++) {
      for (var px = 0; px < patch.width; px++) {
        final i = py * patch.width + px;
        final o = ((patch.y0 + py) * src.width + patch.x0 + px) * 4;
        final c = ColorMath.rgbToLab(
          src.pixels[o],
          src.pixels[o + 1],
          src.pixels[o + 2],
        );
        l[i] = c.l;
        a[i] = c.a;
        b[i] = c.b;
        final m = patch.data[i];
        sumM += m;
        sl += m * c.l;
        sa += m * c.a;
        sb += m * c.b;
      }
    }
    final lab = _LabPatch(
      l,
      a,
      b,
      sumM > 0 ? sl / sumM : 0,
      sumM > 0 ? sa / sumM : 0,
      sumM > 0 ? sb / sumM : 0,
    );
    face.cache[key] = lab;
    return lab;
  }
}

class _LabPatch {
  _LabPatch(this.l, this.a, this.b, this.meanL, this.meanA, this.meanB);
  final Float32List l, a, b;
  final double meanL, meanA, meanB;
}
