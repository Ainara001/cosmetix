import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

/// CIE L*a*b* (D65) conversions. Makeup is applied as shifts in Lab: a shift is
/// the same for every pixel of a zone, so differences between neighbouring
/// pixels (pores, scars, lip lines) are kept exactly.
class Lab {
  const Lab(this.l, this.a, this.b);
  final double l;
  final double a;
  final double b;

  @override
  String toString() => 'Lab($l, $a, $b)';
}

class ColorMath {
  ColorMath._();

  static final Float64List _toLinear = Float64List.fromList([
    for (var i = 0; i < 256; i++) _srgbToLinear(i / 255),
  ]);

  static double _srgbToLinear(double c) =>
      c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

  static double _linearToSrgb(double c) => c <= 0.0031308
      ? 12.92 * c
      : 1.055 * math.pow(c, 1 / 2.4).toDouble() - 0.055;

  // D65 white
  static const _xn = 0.95047, _yn = 1.0, _zn = 1.08883;
  static const _eps = 216 / 24389, _kappa = 24389 / 27;

  static double _f(double t) =>
      t > _eps ? math.pow(t, 1 / 3).toDouble() : (_kappa * t + 16) / 116;

  static double _finv(double t) {
    final t3 = t * t * t;
    return t3 > _eps ? t3 : (116 * t - 16) / _kappa;
  }

  /// sRGB bytes to Lab.
  static Lab rgbToLab(int r, int g, int b) {
    final lr = _toLinear[r], lg = _toLinear[g], lb = _toLinear[b];
    final x = 0.4124564 * lr + 0.3575761 * lg + 0.1804375 * lb;
    final y = 0.2126729 * lr + 0.7151522 * lg + 0.0721750 * lb;
    final z = 0.0193339 * lr + 0.1191920 * lg + 0.9503041 * lb;
    final fx = _f(x / _xn), fy = _f(y / _yn), fz = _f(z / _zn);
    return Lab(116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz));
  }

  /// Lab to sRGB, clamped to the displayable range. Writes into [out] at
  /// [offset] (R, G, B).
  static void labToRgb(
    double l,
    double a,
    double b,
    Uint8List out,
    int offset,
  ) {
    final fy = (l + 16) / 116;
    final fx = fy + a / 500;
    final fz = fy - b / 200;
    final x = _finv(fx) * _xn, y = _finv(fy) * _yn, z = _finv(fz) * _zn;
    final lr = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z;
    final lg = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z;
    final lb = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z;
    out[offset] = _byte(_linearToSrgb(lr.clamp(0.0, 1.0)));
    out[offset + 1] = _byte(_linearToSrgb(lg.clamp(0.0, 1.0)));
    out[offset + 2] = _byte(_linearToSrgb(lb.clamp(0.0, 1.0)));
  }

  static int _byte(double v) => (v * 255).round().clamp(0, 255);

  static Lab colorToLab(Color c) =>
      rgbToLab((c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round());
}
