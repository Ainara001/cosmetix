import 'package:flutter/material.dart';

/// Brand colors taken from the Figma mock-up. Solid colors only (no gradients).
class AppColors {
  AppColors._();

  static const primary = Color(0xFFC88A9B);
  static const primaryDark = Color(0xFFB5647C);
  static const primarySoft = Color(0xFFF6E4E9);
  static const blush = Color(0xFFF7ECEE);
  static const salmon = Color(0xFFE88C90);
  static const sale = Color(0xFFD42F2F);
  static const saleSoft = Color(0xFFFBE4E6);
  static const success = Color(0xFF2E8B63);
  static const successSoft = Color(0xFFE3F3EB);
  static const warning = Color(0xFFE5A23A);
  static const danger = Color(0xFFD64545);
}

/// Colors that change between light and dark theme.
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.text,
    required this.subtext,
    required this.border,
    required this.field,
  });

  final Color background;
  final Color surface;
  final Color text;
  final Color subtext;
  final Color border;
  final Color field;

  static const light = AppPalette(
    background: Color(0xFFF8F4F5),
    surface: Colors.white,
    text: Color(0xFF1E1A1C),
    subtext: Color(0xFF8E8689),
    border: Color(0xFFEBDCE0),
    field: Color(0xFFF1EDEE),
  );

  static const dark = AppPalette(
    background: Color(0xFF161214),
    surface: Color(0xFF231D20),
    text: Color(0xFFF3ECEE),
    subtext: Color(0xFFA89EA2),
    border: Color(0xFF3A3135),
    field: Color(0xFF2C2528),
  );

  @override
  AppPalette copyWith({
    Color? background,
    Color? surface,
    Color? text,
    Color? subtext,
    Color? border,
    Color? field,
  }) {
    return AppPalette(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      text: text ?? this.text,
      subtext: subtext ?? this.subtext,
      border: border ?? this.border,
      field: field ?? this.field,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      text: Color.lerp(text, other.text, t)!,
      subtext: Color.lerp(subtext, other.subtext, t)!,
      border: Color.lerp(border, other.border, t)!,
      field: Color.lerp(field, other.field, t)!,
    );
  }
}

extension PaletteContext on BuildContext {
  AppPalette get pal => Theme.of(this).extension<AppPalette>()!;
}
