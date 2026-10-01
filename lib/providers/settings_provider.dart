import 'package:flutter/material.dart';

import 'package:cosmetix/core/utils/formatters.dart';
import 'package:cosmetix/repositories/settings_repository.dart';

class SettingsProvider extends ChangeNotifier {
  SettingsProvider(this._repo);

  final SettingsRepository _repo;

  bool pushEnabled = true;
  ThemeMode themeMode = ThemeMode.light;
  AppCurrency currency = AppCurrency.kzt;
  String language = 'Русский';

  static const languages = ['Русский'];

  Future<void> load() async {
    try {
      final map = await _repo.all();
      pushEnabled = map['push'] != '0';
      themeMode = map['theme'] == 'dark' ? ThemeMode.dark : ThemeMode.light;
      currency = AppCurrency.fromName(map['currency']);
      language = map['language'] ?? 'Русский';
    } catch (e) {
      debugPrint('settings load failed: $e');
    }
    notifyListeners();
  }

  String priceText(int tenge) => Formatters.price(tenge, currency);

  Future<void> setPush(bool value) async {
    pushEnabled = value;
    notifyListeners();
    await _repo.set('push', value ? '1' : '0');
  }

  Future<void> setTheme(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    await _repo.set('theme', mode == ThemeMode.dark ? 'dark' : 'light');
  }

  Future<void> setCurrency(AppCurrency value) async {
    currency = value;
    notifyListeners();
    await _repo.set('currency', value.name);
  }

  Future<void> setLanguage(String value) async {
    language = value;
    notifyListeners();
    await _repo.set('language', value);
  }
}
