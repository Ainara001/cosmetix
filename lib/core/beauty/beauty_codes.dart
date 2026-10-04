/// Normalized beauty-profile values. The UI and the `users` table keep the
/// Russian labels (the source language of the app); the recommendation logic
/// and the product trait tables use these codes.
enum SkinType {
  dry('dry', 'Сухая'),
  normal('normal', 'Нормальная'),
  oily('oily', 'Жирная'),
  combination('combination', 'Комбинированная'),
  sensitive('sensitive', 'Чувствительная');

  const SkinType(this.code, this.label);
  final String code;
  final String label;

  static SkinType? fromCode(String? v) => _find(values, v, (e) => e.code);
  static SkinType? fromLabel(String? v) => _find(values, v, (e) => e.label);
}

enum Undertone {
  warm('warm', 'Тёплый'),
  cool('cool', 'Холодный'),
  neutral('neutral', 'Нейтральный');

  const Undertone(this.code, this.label);
  final String code;
  final String label;

  static Undertone? fromCode(String? v) => _find(values, v, (e) => e.code);
  static Undertone? fromLabel(String? v) => _find(values, v, (e) => e.label);
}

enum ColorType {
  spring('spring', 'Весна'),
  summer('summer', 'Лето'),
  autumn('autumn', 'Осень'),
  winter('winter', 'Зима');

  const ColorType(this.code, this.label);
  final String code;
  final String label;

  static ColorType? fromCode(String? v) => _find(values, v, (e) => e.code);
  static ColorType? fromLabel(String? v) => _find(values, v, (e) => e.label);
}

enum SkinTone {
  veryLight('very_light', 'Очень светлый'),
  light('light', 'Светлый'),
  medium('medium', 'Средний'),
  tan('tan', 'Смуглый'),
  deep('deep', 'Тёмный');

  const SkinTone(this.code, this.label);
  final String code;
  final String label;

  static SkinTone? fromCode(String? v) => _find(values, v, (e) => e.code);
  static SkinTone? fromLabel(String? v) => _find(values, v, (e) => e.label);
}

enum SkinConcern {
  dryness('dryness', 'Сухость и шелушение'),
  pigmentation('pigmentation', 'Пигментация'),
  acne('acne', 'Акне и высыпания'),
  sensitivity('sensitivity', 'Чувствительность и покраснения'),
  aging('aging', 'Морщины и возраст');

  const SkinConcern(this.code, this.label);
  final String code;
  final String label;

  static SkinConcern? fromCode(String? v) => _find(values, v, (e) => e.code);
  static SkinConcern? fromLabel(String? v) => _find(values, v, (e) => e.label);
}

T? _find<T>(List<T> all, String? v, String Function(T) key) {
  if (v == null) return null;
  final s = v.trim().toLowerCase();
  for (final e in all) {
    if (key(e).toLowerCase() == s) return e;
  }
  return null;
}
