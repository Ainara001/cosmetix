import 'dart:math' as math;

import 'package:cosmetix/core/beauty/beauty_codes.dart';

/// A named colour of a palette (name in Russian, translated with `tr`).
class PaletteColor {
  const PaletteColor(this.name, this.argb);

  final String name;
  final int argb;
}

/// One block of a palette: lips, blush, eyes, clothes, metals...
class PaletteGroup {
  const PaletteGroup(this.title, this.colors);

  /// Russian source title (translated with `tr`).
  final String title;
  final List<PaletteColor> colors;
}

/// Everything that flatters one colour type and what does not.
class SeasonPalette {
  const SeasonPalette({required this.groups, required this.avoid});

  /// lips, blush, eyes, clothes, metals (in this order, see [ColorPalettes]).
  final List<PaletteGroup> groups;
  final List<PaletteColor> avoid;

  /// The makeup colours (lips, blush, eyes): what a lipstick, a blush or an
  /// eyeshadow shade is compared with.
  List<PaletteColor> get flattering => [
    for (final g in groups.take(ColorPalettes.makeupGroupCount)) ...g.colors,
  ];

  /// Every colour of the palette, for a short summary.
  List<PaletteColor> get all => [for (final g in groups) ...g.colors];
}

class ColorPalettes {
  ColorPalettes._();

  /// The first groups of every palette are makeup (see [SeasonPalette]).
  static const makeupGroupCount = 3;

  static const seasons = {
    ColorType.spring: SeasonPalette(
      groups: [
        PaletteGroup('Помада и тинты', [
          PaletteColor('Персиковый', 0xFFF4A582),
          PaletteColor('Коралл', 0xFFEE6F5B),
          PaletteColor('Тёплый розовый', 0xFFF28C8C),
          PaletteColor('Абрикос', 0xFFF2A65A),
          PaletteColor('Тёплый красный', 0xFFE5483F),
          PaletteColor('Карамельный нюд', 0xFFD79A86),
          PaletteColor('Лососёвый', 0xFFF08A6E),
        ]),
        PaletteGroup('Румяна', [
          PaletteColor('Персиковый румянец', 0xFFF7B79A),
          PaletteColor('Коралловый румянец', 0xFFF28B7A),
          PaletteColor('Тёплая роза', 0xFFF4A3A0),
          PaletteColor('Золотистый абрикос', 0xFFF3B27A),
        ]),
        PaletteGroup('Тени для век', [
          PaletteColor('Золотистый беж', 0xFFE8C99A),
          PaletteColor('Тёплый коричневый', 0xFFA9744F),
          PaletteColor('Персик', 0xFFF2B79B),
          PaletteColor('Бирюзовый', 0xFF3FB8AF),
          PaletteColor('Салатовый оливковый', 0xFFA3B86C),
          PaletteColor('Шампань', 0xFFE5C27A),
        ]),
        PaletteGroup('Одежда и аксессуары', [
          PaletteColor('Слоновая кость', 0xFFFFF4DC),
          PaletteColor('Карамель', 0xFFC9955E),
          PaletteColor('Бирюза', 0xFF40C4B8),
          PaletteColor('Яркий коралл', 0xFFFF7F6E),
          PaletteColor('Светло-зелёный', 0xFFA8D86C),
          PaletteColor('Золотисто-жёлтый', 0xFFF5C94C),
          PaletteColor('Тёплый голубой', 0xFF7FC8E6),
        ]),
        PaletteGroup('Металл украшений', [
          PaletteColor('Жёлтое золото', 0xFFD4AF37),
          PaletteColor('Светлая латунь', 0xFFE3C878),
        ]),
      ],
      avoid: [
        PaletteColor('Тёмный винный', 0xFF5C1F33),
        PaletteColor('Серо-коричневый', 0xFF6B5A58),
        PaletteColor('Холодный бордо', 0xFF7A2A4A),
        PaletteColor('Чисто-чёрный', 0xFF121212),
      ],
    ),
    ColorType.summer: SeasonPalette(
      groups: [
        PaletteGroup('Помада и тинты', [
          PaletteColor('Пудровая роза', 0xFFC98B9E),
          PaletteColor('Холодный розовый', 0xFFE5A1B5),
          PaletteColor('Мягкая малина', 0xFFB8537A),
          PaletteColor('Розово-лиловый', 0xFFB97A9B),
          PaletteColor('Ягодный нюд', 0xFFB5838F),
          PaletteColor('Сливочно-розовый', 0xFFD7B5C8),
          PaletteColor('Мягкая вишня', 0xFFA63A5C),
        ]),
        PaletteGroup('Румяна', [
          PaletteColor('Холодная роза', 0xFFE8A5B8),
          PaletteColor('Розово-бежевый', 0xFFD9A5A5),
          PaletteColor('Лавандовый румянец', 0xFFD6A9C9),
          PaletteColor('Малиновая дымка', 0xFFC97B97),
        ]),
        PaletteGroup('Тени для век', [
          PaletteColor('Серо-коричневый тауп', 0xFF8F7B7B),
          PaletteColor('Мягкий серый', 0xFFA7A9B4),
          PaletteColor('Лаванда', 0xFFB9A3D6),
          PaletteColor('Серо-голубой', 0xFF9FB8D6),
          PaletteColor('Дымчатая слива', 0xFF7A5C7A),
          PaletteColor('Розовый беж', 0xFFD9B8B8),
        ]),
        PaletteGroup('Одежда и аксессуары', [
          PaletteColor('Пудрово-голубой', 0xFFB7CBE0),
          PaletteColor('Сиреневый', 0xFFC9B8E0),
          PaletteColor('Нежно-розовый', 0xFFF0C4D4),
          PaletteColor('Голубая сталь', 0xFF8FA6BF),
          PaletteColor('Пыльная роза', 0xFFC9919F),
          PaletteColor('Мягкий белый', 0xFFF3F0F4),
          PaletteColor('Серый графит', 0xFF6D717C),
        ]),
        PaletteGroup('Металл украшений', [
          PaletteColor('Серебро', 0xFFC0C5CE),
          PaletteColor('Розовое золото', 0xFFB76E79),
        ]),
      ],
      avoid: [
        PaletteColor('Оранжевый', 0xFFE8742A),
        PaletteColor('Горчичный', 0xFFC9992B),
        PaletteColor('Тёплый коричневый', 0xFF8A5A3C),
        PaletteColor('Чисто-чёрный', 0xFF121212),
      ],
    ),
    ColorType.autumn: SeasonPalette(
      groups: [
        PaletteGroup('Помада и тинты', [
          PaletteColor('Терракота', 0xFFB5532F),
          PaletteColor('Кирпичный', 0xFF9C4A35),
          PaletteColor('Коричневый нюд', 0xFFA9705A),
          PaletteColor('Ржавый красный', 0xFFB03A2E),
          PaletteColor('Медный коралл', 0xFFD0704A),
          PaletteColor('Карамель', 0xFFC08A62),
          PaletteColor('Бордово-коричневый', 0xFF7A3B2E),
        ]),
        PaletteGroup('Румяна', [
          PaletteColor('Персиково-терракотовый', 0xFFD98A6C),
          PaletteColor('Кирпично-розовый', 0xFFC0705C),
          PaletteColor('Бронзовый румянец', 0xFFC98B5C),
          PaletteColor('Тёплый абрикос', 0xFFE09A6B),
        ]),
        PaletteGroup('Тени для век', [
          PaletteColor('Бронза', 0xFFB8863B),
          PaletteColor('Оливковый', 0xFF7A8450),
          PaletteColor('Шоколад', 0xFF5A3A29),
          PaletteColor('Медный', 0xFFB87333),
          PaletteColor('Хвойный зелёный', 0xFF3F5E3A),
          PaletteColor('Золотисто-коричневый', 0xFFA67B3A),
        ]),
        PaletteGroup('Одежда и аксессуары', [
          PaletteColor('Хаки', 0xFF7A8450),
          PaletteColor('Горчичный', 0xFFC98B2F),
          PaletteColor('Верблюжий', 0xFFC19A6B),
          PaletteColor('Ржавый', 0xFFB7410E),
          PaletteColor('Бирюзово-зелёный', 0xFF2E7D6B),
          PaletteColor('Шоколадный', 0xFF4E342E),
          PaletteColor('Кремовый', 0xFFF1E3C6),
        ]),
        PaletteGroup('Металл украшений', [
          PaletteColor('Золото', 0xFFD4AF37),
          PaletteColor('Медь', 0xFFB87333),
          PaletteColor('Бронза', 0xFF9C6B30),
        ]),
      ],
      avoid: [
        PaletteColor('Холодный розовый', 0xFFE5A1B5),
        PaletteColor('Фуксия', 0xFFD6336C),
        PaletteColor('Серебристо-серый', 0xFFA8A8B0),
        PaletteColor('Ледяной голубой', 0xFFC5E3F5),
      ],
    ),
    ColorType.winter: SeasonPalette(
      groups: [
        PaletteGroup('Помада и тинты', [
          PaletteColor('Истинный красный', 0xFFC8102E),
          PaletteColor('Малиновый', 0xFFC2185B),
          PaletteColor('Вишнёвый', 0xFF9B1B30),
          PaletteColor('Винный', 0xFF7A1F3D),
          PaletteColor('Тёмный бордо', 0xFF6B2D3C),
          PaletteColor('Фуксия', 0xFFD6336C),
          PaletteColor('Ягодный', 0xFF8E1E4A),
          PaletteColor('Сливовый', 0xFF5B2A56),
          PaletteColor('Яркий розовый', 0xFFE5266F),
        ]),
        PaletteGroup('Румяна', [
          PaletteColor('Холодная роза', 0xFFD96C8C),
          PaletteColor('Ягодный румянец', 0xFFB5446E),
          PaletteColor('Малиново-розовый', 0xFFD1568A),
          PaletteColor('Ледяная роза', 0xFFF0B8CF),
        ]),
        PaletteGroup('Тени для век', [
          PaletteColor('Графит', 0xFF3A3A3F),
          PaletteColor('Тёмно-синий', 0xFF1F3C88),
          PaletteColor('Серебристо-серый', 0xFFA8A8B4),
          PaletteColor('Изумруд', 0xFF0F7B5F),
          PaletteColor('Сливовый', 0xFF5B2A56),
          PaletteColor('Чёрный', 0xFF1A1A1D),
          PaletteColor('Ледяной лиловый', 0xFFC7B8E0),
        ]),
        PaletteGroup('Одежда и аксессуары', [
          PaletteColor('Чисто-белый', 0xFFFFFFFF),
          PaletteColor('Чёрный', 0xFF111111),
          PaletteColor('Королевский синий', 0xFF2347A6),
          PaletteColor('Изумрудный', 0xFF0F8A5F),
          PaletteColor('Яркий розовый', 0xFFE5266F),
          PaletteColor('Ледяной голубой', 0xFFC5E3F5),
          PaletteColor('Истинный красный', 0xFFC8102E),
          PaletteColor('Холодный серый', 0xFFB0B0BA),
        ]),
        PaletteGroup('Металл украшений', [
          PaletteColor('Серебро', 0xFFC0C5CE),
          PaletteColor('Платина', 0xFFE0E2E8),
          PaletteColor('Белое золото', 0xFFD8D4CC),
        ]),
      ],
      avoid: [
        PaletteColor('Персиковый', 0xFFF4A582),
        PaletteColor('Золотисто-оранжевый', 0xFFE0A030),
        PaletteColor('Тёплый беж', 0xFFD9B48A),
        PaletteColor('Горчичный', 0xFFC9992B),
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
      (1 - paletteDistance(shade, type) / 32).clamp(0.0, 1.0);

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
