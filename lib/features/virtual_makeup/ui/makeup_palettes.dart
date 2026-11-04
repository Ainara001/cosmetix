import 'dart:ui' show Color;

import '../domain/makeup_look.dart';

/// A named colour the user can pick. The names are Russian source texts and are
/// translated with `tr` where they are shown.
class MakeupSwatch {
  const MakeupSwatch(this.name, this.color);
  final String name;
  final Color color;
}

class MakeupPalettes {
  MakeupPalettes._();

  static const lips = [
    MakeupSwatch('Винный', Color(0xFFB03A48)),
    MakeupSwatch('Розовый', Color(0xFFD9566B)),
    MakeupSwatch('Коралловый', Color(0xFFC75B4A)),
    MakeupSwatch('Ягодный', Color(0xFF8E2F3C)),
    MakeupSwatch('Нюд', Color(0xFFE8998D)),
    MakeupSwatch('Сливовый', Color(0xFF6B2A3A)),
  ];

  static const eyeshadow = [
    MakeupSwatch('Мальва', Color(0xFF8A6A7A)),
    MakeupSwatch('Бронза', Color(0xFFB08A6A)),
    MakeupSwatch('Серо-синий', Color(0xFF5B6B8A)),
    MakeupSwatch('Шалфей', Color(0xFF6A8A6F)),
    MakeupSwatch('Дымчатый', Color(0xFF3E3A46)),
    MakeupSwatch('Шампань', Color(0xFFC9A27A)),
  ];

  static const blush = [
    MakeupSwatch('Розовый', Color(0xFFE08A8A)),
    MakeupSwatch('Персиковый', Color(0xFFF0A08A)),
    MakeupSwatch('Малиновый', Color(0xFFD96F7D)),
    MakeupSwatch('Терракотовый', Color(0xFFC98A7A)),
    MakeupSwatch('Нежный', Color(0xFFE8B0A8)),
  ];

  static List<MakeupSwatch> of(MakeupZone zone) => switch (zone) {
    MakeupZone.lips => lips,
    MakeupZone.eyeshadow => eyeshadow,
    MakeupZone.blush => blush,
  };

  /// Russian source name of a zone (translated where shown).
  static String zoneName(MakeupZone zone) => switch (zone) {
    MakeupZone.lips => 'Помада',
    MakeupZone.eyeshadow => 'Тени',
    MakeupZone.blush => 'Румяна',
  };
}
