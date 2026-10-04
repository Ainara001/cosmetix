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
  });

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
      '${colorType?.code}|${(concerns.map((c) => c.code).toList()..sort()).join(',')}';

  factory BeautyProfile.fromLabels({
    String? skinType,
    String? skinTone,
    String? undertone,
    String? colorType,
    List<String> concerns = const [],
    String? source,
    double? confidence,
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
  );
}
