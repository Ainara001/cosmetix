import 'package:flutter/material.dart';

/// Text styles without colors: the color comes from the theme / the caller.
class AppTextStyles {
  AppTextStyles._();

  static const h1 = TextStyle(fontSize: 30, fontWeight: FontWeight.w700);
  static const h2 = TextStyle(fontSize: 22, fontWeight: FontWeight.w700);
  static const title = TextStyle(fontSize: 18, fontWeight: FontWeight.w700);
  static const subtitle = TextStyle(fontSize: 15, fontWeight: FontWeight.w600);
  static const body = TextStyle(fontSize: 14, fontWeight: FontWeight.w400);
  static const bodyBold = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
  static const small = TextStyle(fontSize: 12, fontWeight: FontWeight.w400);
  static const caption = TextStyle(fontSize: 11, fontWeight: FontWeight.w400);
  static const label = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.4,
  );
}
