import 'dart:math' as math;

import '../domain/makeup_look.dart';
import 'color_math.dart';
import 'makeup_backend.dart';
import 'pigment_params.dart';
import 'zone_gate.dart';
import 'rgba_image.dart';

/// Stage 2 engine: a PIGMENT layer over the skin, mixed in linear light.
///
/// The product colour is mixed with the colour the zone really has, with the
/// opacity of the product, the way light mixes: the average colour of the zone
/// after the makeup is `(1 - opacity) * what the zone was + opacity * the
/// pigment` in linear light. A cool pink over warm skin therefore gives a colour
/// BETWEEN the two, never a colder one than both (the lilac cheeks of the first
/// engine).
///
/// Every pixel is multiplied by the same per-channel gain (mix average divided
/// by zone average), so the relative differences between pixels stay: pores,
/// scars, spots, redness, lip lines keep their contrast, and a very dark pixel
/// (the line between the lips) stays dark and keeps its own hue instead of being
/// pushed into blue by an added colour shift. Nothing is filtered or replaced.
///
/// A colour gate keeps paint off things that are not the zone: pixels whose
/// colour is far from the typical colour of the zone (a finger or a nail at the
/// mouth, teeth, hair, a glasses frame) get little or no paint.
///
/// The contract is that of every engine (see [MakeupBackend]): a pixel outside
/// every zone, with protection 1, or with a negligible effect, is returned byte
/// for byte as in the photo.
class PigmentBackend implements SyncMakeupBackend {
  const PigmentBackend({this.params = PigmentParams.standard});

  final PigmentParams params;

  @override
  String get id => 'pigment-v2';

  @override
  BackendCapabilities get capabilities =>
      const BackendCapabilities(supportsReference: false, runsOnDevice: true);

  static double _luma(double r, double g, double b) =>
      0.2126729 * r + 0.7151522 * g + 0.0721750 * b;

  static double _ease(double e0, double e1, double x) {
    final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

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
    for (final zone in MakeupZone.values) {
      final look = request.look.of(zone);
      if (!look.active) continue;
      final patch = face.maskOf(zone);
      if (patch.isEmpty) continue;
      final z = ZoneGate.of(face, zone, patch, params);
      final alpha = (look.opacity ?? params.opacityOf(zone)).clamp(0.0, 1.0);
      final c = look.color;
      final pig = [
        ColorMath.srgbToLinear(c.r),
        ColorMath.srgbToLinear(c.g),
        ColorMath.srgbToLinear(c.b),
      ];
      // the average colour of the zone becomes the mix: this gain, per channel
      final mix = List<double>.generate(
        3,
        (k) => (1 - alpha) * z.ref[k] + alpha * pig[k],
      );
      final gain = List<double>.generate(
        3,
        (k) => (mix[k] / z.ref[k]).clamp(params.minGain, params.maxGain),
      );
      final yRef = _luma(z.ref[0], z.ref[1], z.ref[2]);
      final yMix = _luma(mix[0], mix[1], mix[2]);
      final gainY = (yMix / yRef).clamp(params.minGain, params.maxGain);
      // keep the contrast of the lightness texture as it was seen (see params)
      final lRef = ColorMath.lightnessOfLuminance(yRef);
      final lMix = ColorMath.lightnessOfLuminance(yMix);
      final texture = (lMix <= 0 ? 1.0 : lRef / lMix).clamp(
        params.textureMin,
        params.textureMax,
      );
      final top0 = math.max(z.ref[0], math.max(z.ref[1], z.ref[2]));
      final satRef =
          (top0 - math.min(z.ref[0], math.min(z.ref[1], z.ref[2]))) / top0;
      final colourTexture = params.colourTextureOf(zone);
      final k = look.intensity;
      for (var py = 0; py < patch.height; py++) {
        final y = patch.y0 + py;
        for (var px = 0; px < patch.width; px++) {
          final i = py * patch.width + px;
          final m = patch.data[i];
          if (m <= 0) continue;
          final x = patch.x0 + px;
          var p = m * k * z.gate[i];
          if (protection != null) p *= 1 - protection.at(x, y);
          if (p < _minEffect) continue;
          final o = (y * w + x) * 4;
          final lr = ColorMath.srgbByteToLinear(out.pixels[o]);
          final lg = ColorMath.srgbByteToLinear(out.pixels[o + 1]);
          final lb = ColorMath.srgbByteToLinear(out.pixels[o + 2]);
          final rho = _luma(lr, lg, lb) / yRef; // lightness against the zone
          // a highlight (much lighter than the zone and nearly colourless) stays
          // a highlight
          final top = math.max(lr, math.max(lg, lb));
          final grey =
              1 - (top - math.min(lr, math.min(lg, lb))) / math.max(top, 1e-6);
          p *=
              1 -
              params.highlightKeep *
                  _ease(params.highlightStart, params.highlightEnd, rho) *
                  _ease(0.6, 0.85, grey);
          if (p < _minEffect) continue;
          // dark and pale pixels keep their hue: one common gain instead of one per
          // channel
          final sat = 1 - grey;
          final wPale = satRef < 0.05
              ? 1.0
              : _ease(params.paleStart, params.paleEnd, sat / satRef);
          final wDark = _ease(params.darkStart, params.darkEnd, rho) * wPale;
          final tex = texture == 1
              ? 1.0
              : math.pow(math.max(rho, 0.1), texture - 1).toDouble();
          final lin = [lr, lg, lb];
          // the part of the pixel's colour that differs from its zone's: kept in
          // full, or reduced for the lips (see PigmentParams.lipsColourTexture)
          final qs = colourTexture;
          for (var ch = 0; ch < 3; ch++) {
            var g = (gainY + (gain[ch] - gainY) * wDark) * tex;
            if (qs < 1 && rho > 1e-4) {
              // q = (pixel / zone colour) / (pixel / zone lightness)
              final q = (lin[ch] / z.ref[ch]) / rho;
              g *= math.pow(math.max(q, 1e-3), qs - 1).toDouble();
            }
            out.pixels[o + ch] = ColorMath.linearToSrgbByte(
              lin[ch] * (1 + p * (g - 1)),
            );
          }
        }
      }
    }
    return out;
  }
}
