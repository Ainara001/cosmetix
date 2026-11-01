import 'dart:math' as math;

import 'package:cosmetix/core/beauty/beauty_codes.dart';

/// A named colour of a palette (name in Russian, translated with `tr`).
class PaletteColor {
  const PaletteColor(this.name, this.argb);

  final String name;
  final int argb;
}

/// What flatters one colour type (makeup shades: lips, cheeks, eyes) and what
/// does not.
class SeasonPalette {
  const SeasonPalette({required this.flattering, required this.avoid});

  final List<PaletteColor> flattering;
  final List<PaletteColor> avoid;
}

class ColorPalettes {
  ColorPalettes._();

  static const seasons = {
    ColorType.spring: SeasonPalette(
      flattering: [
        PaletteColor('Персиковый', 0xFFF4A582),
        PaletteColor('Коралл', 0xFFEE6F5B),
        PaletteColor('Тёплый розовый', 0xFFF28C8C),
        PaletteColor('Золотистый беж', 0xFFE8B98A),
        PaletteColor('Абрикос', 0xFFF2A65A),
        PaletteColor('Тёплый красный', 0xFFE5483F),
        PaletteColor('Карамельный нюд', 0xFFD79A86),
      ],
      avoid: [
        PaletteColor('Тёмный винный', 0xFF5C1F33),
        PaletteColor('Серо-коричневый', 0xFF6B5A58),
        PaletteColor('Холодный бордо', 0xFF7A2A4A),
      ],
    ),
    ColorType.summer: SeasonPalette(
      flattering: [
        PaletteColor('Пудровая роза', 0xFFC98B9E),
        PaletteColor('Холодный розовый', 0xFFE5A1B5),
        PaletteColor('Лаванда', 0xFFB9A3D6),
        PaletteColor('Мягкая малина', 0xFFB8537A),
        PaletteColor('Холодный нюд', 0xFFC9A0A0),
        PaletteColor('Серо-голубой', 0xFF9FB8D6),
        PaletteColor('Сливочно-розовый', 0xFFD7B5C8),
      ],
      avoid: [
        PaletteColor('Оранжевый', 0xFFE8742A),
        PaletteColor('Горчичный', 0xFFC9992B),
        PaletteColor('Тёплый коричневый', 0xFF8A5A3C),
      ],
    ),
    ColorType.autumn: SeasonPalette(
      flattering: [
        PaletteColor('Терракота', 0xFFB5532F),
        PaletteColor('Кирпичный', 0xFF9C4A35),
        PaletteColor('Тёплый коричневый', 0xFF8A5A3C),
        PaletteColor('Бронза', 0xFFB8863B),
        PaletteColor('Карамель', 0xFFC08A62),
        PaletteColor('Оливковый', 0xFF7A8450),
        PaletteColor('Медный коралл', 0xFFD0704A),
      ],
      avoid: [
        PaletteColor('Холодный розовый', 0xFFE5A1B5),
        PaletteColor('Фуксия', 0xFFD6336C),
        PaletteColor('Серебристо-серый', 0xFFA8A8B0),
      ],
    ),
    ColorType.winter: SeasonPalette(
      flattering: [
        PaletteColor('Винный', 0xFF7A1F3D),
        PaletteColor('Малиновый', 0xFFC2185B),
        PaletteColor('Холодный красный', 0xFFC8102E),
        PaletteColor('Сливовый', 0xFF5B2A56),
        PaletteColor('Ягодный', 0xFF8E1E4A),
        PaletteColor('Фуксия', 0xFFD6336C),
        PaletteColor('Графит', 0xFF3A3A3F),
      ],
      avoid: [
        PaletteColor('Персиковый', 0xFFF4A582),
        PaletteColor('Золотисто-оранжевый', 0xFFE0A030),
        PaletteColor('Тёплый беж', 0xFFD9B48A),
      ],
    ),
  };

  /// Typical skin colour per tone and undertone, for matching a foundation or
  /// cushion shade.
  static const skin = {
    SkinTone.veryLight: {
      Undertone.warm: 0xFFF3D9C4,
      Undertone.cool: 0xFFF5DDD8,
      Undertone.neutral: 0xFFF4DCCB,
    },
    SkinTone.light: {
      Undertone.warm: 0xFFEBC6A3,
      Undertone.cool: 0xFFEDC9BC,
      Undertone.neutral: 0xFFECC8AD,
    },
    SkinTone.medium: {
      Undertone.warm: 0xFFD9A57B,
      Undertone.cool: 0xFFD7A793,
      Undertone.neutral: 0xFFD8A585,
    },
    SkinTone.tan: {
      Undertone.warm: 0xFFBC8558,
      Undertone.cool: 0xFFB98768,
      Undertone.neutral: 0xFFBB8560,
    },
    SkinTone.deep: {
      Undertone.warm: 0xFF8D5A3B,
      Undertone.cool: 0xFF8A5C4A,
      Undertone.neutral: 0xFF8B5B42,
    },
  };
}

/// Compares colours the way an eye does (CIE Lab distance), so a "berry"
/// lip tint can be told from a "coral" one, and a light beige base from a
/// tan one.
class ShadeMatcher {
  ShadeMatcher._();

  /// Distance in Lab space (about 2 is just noticeable, 40+ is another colour).
  static double distance(int a, int b) {
    final x = _lab(a), y = _lab(b);
    return math.sqrt(
      math.pow(x[0] - y[0], 2) +
          math.pow(x[1] - y[1], 2) +
          math.pow(x[2] - y[2], 2),
    );
  }

  /// Distance to the nearest flattering colour of [type].
  static double paletteDistance(int shade, ColorType type) {
    var best = double.infinity;
    for (final c in ColorPalettes.seasons[type]!.flattering) {
      final d = distance(shade, c.argb);
      if (d < best) best = d;
    }
    return best;
  }

  /// 0..1: how close [shade] is to the palette of [type] (1 = same colour).
  static double similarity(int shade, ColorType type) =>
      (1 - paletteDistance(shade, type) / 38).clamp(0.0, 1.0);

  /// The colour type whose palette is closest to [shade].
  static ColorType closestSeason(int shade) {
    var best = ColorType.spring;
    var bestD = double.infinity;
    for (final t in ColorType.values) {
      final d = paletteDistance(shade, t);
      if (d < bestD) {
        bestD = d;
        best = t;
      }
    }
    return best;
  }

  /// Warm for spring/autumn shades, cool for summer/winter ones.
  static Undertone undertoneOf(int shade) {
    final t = closestSeason(shade);
    return t == ColorType.spring || t == ColorType.autumn
        ? Undertone.warm
        : Undertone.cool;
  }

  /// 0..1 for a foundation / cushion: how close the shade is to the person's
  /// skin ([tone] and [undertone] known; unknown parts use the middle).
  static double skinSimilarity(int shade, SkinTone tone, Undertone? undertone) {
    final row = ColorPalettes.skin[tone]!;
    final target = row[undertone ?? Undertone.neutral]!;
    return (1 - distance(shade, target) / 26).clamp(0.0, 1.0);
  }

  static List<double> _lab(int argb) {
    double lin(int c) {
      final v = c / 255;
      return v <= 0.04045
          ? v / 12.92
          : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    }

    final r = lin((argb >> 16) & 0xFF);
    final g = lin((argb >> 8) & 0xFF);
    final b = lin(argb & 0xFF);
    final x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047;
    final y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b;
    final z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883;
    double f(double t) =>
        t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
    final fx = f(x), fy = f(y), fz = f(z);
    return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)];
  }
}
