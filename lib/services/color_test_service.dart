import 'package:flutter/material.dart';

class ColorOption {
  const ColorOption(this.title, this.color, {this.warm = 0, this.depth = 0});

  final String title;
  final Color color;

  /// Positive = warm undertone, negative = cool.
  final int warm;

  /// Positive = deep (dark) coloring, negative = light.
  final int depth;
}

class ColorQuestion {
  const ColorQuestion(this.section, this.question, this.options);

  final String section;
  final String question;
  final List<ColorOption> options;
}

class ColorTestResult {
  const ColorTestResult({
    required this.colorType,
    required this.undertone,
    required this.skinTone,
  });

  final String colorType;
  final String undertone;
  final String skinTone;

  String get description {
    switch (colorType) {
      case 'Весна':
        return 'Светлый тёплый тип: вам идут персиковые, коралловые и '
            'золотистые оттенки, лёгкие текстуры и тёплые нюды.';
      case 'Лето':
        return 'Светлый холодный тип: выбирайте розовые, лавандовые и '
            'приглушённые оттенки с холодным подтоном.';
      case 'Осень':
        return 'Глубокий тёплый тип: вам подходят терракотовые, медные и '
            'тёплые коричневые оттенки.';
      default:
        return 'Контрастный холодный тип: яркие ягодные, винные и чистые '
            'холодные оттенки подчеркнут вашу внешность.';
    }
  }
}

class ColorTestService {
  ColorTestService._();

  static const questions = [
    ColorQuestion('Глаза', 'Какого цвета ваши глаза?', [
      ColorOption('Голубые / серые', Color(0xFF9DB7CF), warm: -1, depth: -1),
      ColorOption('Зелёные / ореховые', Color(0xFF8BA66B), warm: 1, depth: 0),
      ColorOption('Светло-карие', Color(0xFFB98A55), warm: 1, depth: 0),
      ColorOption('Тёмно-карие / чёрные', Color(0xFF4A3426), warm: 0, depth: 2),
    ]),
    ColorQuestion('Волосы', 'Какой у вас натуральный цвет волос?', [
      ColorOption(
        'Светлый блонд / русый',
        Color(0xFFE5C99A),
        warm: 0,
        depth: -2,
      ),
      ColorOption('Рыжий / медный', Color(0xFFC0693A), warm: 2, depth: 0),
      ColorOption('Шатен / каштановый', Color(0xFF8A5A3C), warm: 0, depth: 1),
      ColorOption(
        'Чёрный / тёмный брюнет',
        Color(0xFF2B2220),
        warm: -1,
        depth: 2,
      ),
    ]),
    ColorQuestion('Кожа', 'Какой у вас естественный цвет кожи?', [
      ColorOption(
        'Очень светлая, фарфоровая',
        Color(0xFFF7E4DA),
        warm: 0,
        depth: -2,
      ),
      ColorOption('Светлая с румянцем', Color(0xFFF2CDBB), warm: 0, depth: -1),
      ColorOption('Оливковая / средняя', Color(0xFFD9AE86), warm: 1, depth: 1),
      ColorOption('Смуглая / тёмная', Color(0xFF9C6B4A), warm: 0, depth: 2),
    ]),
    ColorQuestion('Солнце', 'Как кожа реагирует на солнце?', [
      ColorOption('Сразу краснею', Color(0xFFE59A8E), warm: -1, depth: -1),
      ColorOption(
        'Краснею, потом загораю',
        Color(0xFFE2B190),
        warm: 0,
        depth: 0,
      ),
      ColorOption('Загораю легко', Color(0xFFC98E62), warm: 1, depth: 1),
      ColorOption('Почти не обгораю', Color(0xFF8E5E40), warm: 0, depth: 2),
    ]),
    ColorQuestion(
      'Румянец',
      'Какой у вас естественный оттенок губ и румянца?',
      [
        ColorOption('Холодный розовый', Color(0xFFE5A1B5), warm: -2, depth: 0),
        ColorOption('Персиковый', Color(0xFFF2B497), warm: 2, depth: -1),
        ColorOption('Коралловый', Color(0xFFE7806B), warm: 1, depth: 0),
        ColorOption(
          'Ягодный / бордовый',
          Color(0xFF8E3A55),
          warm: -1,
          depth: 2,
        ),
      ],
    ),
  ];

  static const veinQuestion = [
    (
      'Синие / Фиолетовые',
      'Указывает на холодный подтон',
      Color(0xFFC98B9C),
      -3,
    ),
    ('Зелёные / Оливковые', 'Указывает на тёплый подтон', Color(0xFF4F9461), 3),
    (
      'Смешанные (Оба цвета)',
      'Указывает на нейтральный подтон',
      Color(0xFF8A8083),
      0,
    ),
  ];

  /// [warm] and [depth] are the sums of the chosen options; [vein] is the
  /// score of the veins test (-3 cool, 0 neutral, 3 warm).
  static ColorTestResult compute({
    required int warm,
    required int depth,
    required int vein,
  }) {
    final totalWarm = warm + vein;
    final undertone = totalWarm >= 2
        ? 'Тёплый'
        : totalWarm <= -2
        ? 'Холодный'
        : 'Нейтральный';
    final isWarm = totalWarm > 0 || (totalWarm == 0 && vein >= 0 && warm >= 0);
    final isDeep = depth >= 2;
    final String type;
    if (isWarm) {
      type = isDeep ? 'Осень' : 'Весна';
    } else {
      type = isDeep ? 'Зима' : 'Лето';
    }
    final tone = depth <= -4
        ? 'Очень светлый'
        : depth <= -1
        ? 'Светлый'
        : depth <= 3
        ? 'Средний'
        : depth <= 6
        ? 'Смуглый'
        : 'Тёмный';
    return ColorTestResult(
      colorType: type,
      undertone: undertone,
      skinTone: tone,
    );
  }
}
