import 'package:cosmetix/core/beauty/beauty_codes.dart';

/// How the profile was determined.
enum BeautySource {
  questionnaire('questionnaire'),
  questionnairePhoto('questionnaire_photo');

  const BeautySource(this.code);
  final String code;

  static BeautySource fromCode(String? v) => BeautySource.values.firstWhere(
    (s) => s.code == v,
    orElse: () => BeautySource.questionnaire,
  );
}

/// Normalized beauty profile used by the recommendation logic.
class BeautyProfile {
  const BeautyProfile({
    this.skinType,
    this.skinTone,
    this.undertone,
    this.colorType,
    this.concerns = const {},
    this.source = BeautySource.questionnaire,
    this.confidence,
    this.preferences = const {},
    this.age,
  });

  /// The careful age of the user (see `AgeSafety`), null when not given.
  final int? age;

  /// Personal preferences the user ticked (codes of [Preferences]).
  final Set<String> preferences;

  final SkinType? skinType;
  final SkinTone? skinTone;
  final Undertone? undertone;
  final ColorType? colorType;
  final Set<SkinConcern> concerns;
  final BeautySource source;

  /// Confidence of the optional photo analysis (0..1), if it was used.
  final double? confidence;

  /// The Beauty Test is considered completed once a color type is known.
  bool get isComplete => colorType != null;

  /// Changes whenever something that affects recommendations changes.
  String get signature =>
      '${skinType?.code}|${skinTone?.code}|${undertone?.code}|'
      '${colorType?.code}|${(concerns.map((c) => c.code).toList()..sort()).join(',')}|'
      '${(preferences.toList()..sort()).join(',')}|$age';

  factory BeautyProfile.fromLabels({
    String? skinType,
    String? skinTone,
    String? undertone,
    String? colorType,
    List<String> concerns = const [],
    String? source,
    double? confidence,
    Set<String> preferences = const {},
    int? age,
  }) => BeautyProfile(
    skinType: SkinType.fromLabel(skinType),
    skinTone: SkinTone.fromLabel(skinTone),
    undertone: Undertone.fromLabel(undertone),
    colorType: ColorType.fromLabel(colorType),
    concerns: {
      for (final c in concerns)
        if (SkinConcern.fromLabel(c) != null) SkinConcern.fromLabel(c)!,
    },
    source: BeautySource.fromCode(source),
    confidence: confidence,
    preferences: preferences,
    age: age,
  );
}

/// Personal preferences that gently shift the ranking (never a hard filter:
/// the blacklist is the only hard rule).
class Preferences {
  Preferences._();

  static const fragranceFree = 'fragrance_free';
  static const natural = 'natural';

  static const all = [fragranceFree, natural];

  /// Russian source label (translated with `tr`).
  static String label(String code) => switch (code) {
    fragranceFree => 'Без отдушки',
    natural => 'Натуральный состав',
    _ => code,
  };

  static Set<String> parse(String? raw) => {
    for (final c in (raw ?? '').split('|'))
      if (all.contains(c)) c,
  };

  static String encode(Set<String> codes) =>
      (codes.where(all.contains).toList()..sort()).join('|');
}
