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

  /// An sRGB byte as linear light, 0..1 (the space where colours MIX like
  /// light does).
  static double srgbByteToLinear(int v) => _toLinear[v];

  /// The lightness L* (0..100) of a linear-light luminance Y (0..1).
  static double lightnessOfLuminance(double y) {
    final t = y.clamp(0.0, 1.0);
    return t > _eps ? 116 * math.pow(t, 1 / 3).toDouble() - 16 : _kappa * t;
  }

  /// An sRGB channel in 0..1 (a Flutter colour channel) as linear light.
  static double srgbToLinear(double c) => _srgbToLinear(c.clamp(0.0, 1.0));

  /// Linear light to an sRGB byte (clamped to the displayable range).
  static int linearToSrgbByte(double linear) =>
      _byte(_linearToSrgb(linear.clamp(0.0, 1.0)));

  static Lab colorToLab(Color c) =>
      rgbToLab((c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round());

  /// The CIEDE2000 colour difference of two Lab colours (Sharma, Wu, Dalal 2005).
  /// About 1 is the smallest difference an observer notices side by side; this
  /// is a measure of two colours, not of how a product looks in real life.
  static double deltaE2000(Lab c1, Lab c2) {
    double rad(double d) => d * math.pi / 180;
    double deg(double r) => r * 180 / math.pi;
    final cab1 = math.sqrt(c1.a * c1.a + c1.b * c1.b);
    final cab2 = math.sqrt(c2.a * c2.a + c2.b * c2.b);
    final cabMean = (cab1 + cab2) / 2;
    final g =
        0.5 *
        (1 -
            math.sqrt(
              math.pow(cabMean, 7) / (math.pow(cabMean, 7) + math.pow(25, 7)),
            ));
    final a1 = (1 + g) * c1.a, a2 = (1 + g) * c2.a;
    final cp1 = math.sqrt(a1 * a1 + c1.b * c1.b);
    final cp2 = math.sqrt(a2 * a2 + c2.b * c2.b);
    double hue(double b, double a) {
      if (a == 0 && b == 0) return 0;
      final h = deg(math.atan2(b, a));
      return h < 0 ? h + 360 : h;
    }

    final hp1 = hue(c1.b, a1), hp2 = hue(c2.b, a2);
    final dl = c2.l - c1.l;
    final dc = cp2 - cp1;
    double dh;
    if (cp1 * cp2 == 0) {
      dh = 0;
    } else if ((hp2 - hp1).abs() <= 180) {
      dh = hp2 - hp1;
    } else if (hp2 - hp1 > 180) {
      dh = hp2 - hp1 - 360;
    } else {
      dh = hp2 - hp1 + 360;
    }
    final dH = 2 * math.sqrt(cp1 * cp2) * math.sin(rad(dh / 2));
    final lMean = (c1.l + c2.l) / 2;
    final cpMean = (cp1 + cp2) / 2;
    double hMean;
    if (cp1 * cp2 == 0) {
      hMean = hp1 + hp2;
    } else if ((hp1 - hp2).abs() <= 180) {
      hMean = (hp1 + hp2) / 2;
    } else if (hp1 + hp2 < 360) {
      hMean = (hp1 + hp2 + 360) / 2;
    } else {
      hMean = (hp1 + hp2 - 360) / 2;
    }
    final t =
        1 -
        0.17 * math.cos(rad(hMean - 30)) +
        0.24 * math.cos(rad(2 * hMean)) +
        0.32 * math.cos(rad(3 * hMean + 6)) -
        0.20 * math.cos(rad(4 * hMean - 63));
    final dTheta = 30 * math.exp(-math.pow((hMean - 275) / 25, 2));
    final rc =
        2 *
        math.sqrt(
          math.pow(cpMean, 7) / (math.pow(cpMean, 7) + math.pow(25, 7)),
        );
    final sl =
        1 +
        (0.015 * math.pow(lMean - 50, 2)) /
            math.sqrt(20 + math.pow(lMean - 50, 2));
    final sc = 1 + 0.045 * cpMean;
    final sh = 1 + 0.015 * cpMean * t;
    final rt = -math.sin(rad(2 * dTheta)) * rc;
    final x = dl / sl, y = dc / sc, z = dH / sh;
    return math.sqrt(x * x + y * y + z * z + rt * y * z);
  }
}
