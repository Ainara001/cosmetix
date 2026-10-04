import 'package:cosmetix/core/i18n/translations_en.dart';
import 'package:cosmetix/core/i18n/translations_kk.dart';

/// UI languages. Source strings in the code are Russian; other languages are
/// looked up by the Russian text.
enum AppLang {
  ru('ru', 'Русский', 'Russian'),
  en('en', 'English', 'English'),
  kk('kk', 'Қазақша', 'Kazakh');

  const AppLang(this.code, this.label, this.englishName);

  final String code;
  final String label;

  /// For prompts to the AI.
  final String englishName;

  static AppLang fromCode(String? code) => AppLang.values.firstWhere(
    (l) => l.code == code,
    orElse: () => AppLang.ru,
  );
}

/// Current UI language (set by SettingsProvider; the app is rebuilt on change).
AppLang currentLang = AppLang.ru;

/// Translates a Russian UI string. Unknown strings stay as they are.
String tr(String ru) => switch (currentLang) {
  AppLang.ru => ru,
  AppLang.en => translationsEn[ru] ?? ru,
  AppLang.kk => translationsKk[ru] ?? ru,
};

/// Translates a template with `{name}` placeholders and fills them in.
String trf(String ruTemplate, Map<String, Object?> args) {
  var text = tr(ruTemplate);
  args.forEach((k, v) => text = text.replaceAll('{$k}', '$v'));
  return text;
}
