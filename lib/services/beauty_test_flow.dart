import 'package:cosmetix/core/beauty/beauty_codes.dart';
import 'package:cosmetix/models/ai_models.dart';
import 'package:cosmetix/models/beauty_profile.dart';
import 'package:cosmetix/services/ai/beauty_profile_merger.dart';
import 'package:cosmetix/services/color_test_service.dart';

/// Skin questions of the Beauty Test (added after the colour questions).
class SkinTestQuestions {
  SkinTestQuestions._();

  /// "How does your skin feel a couple of hours after washing?"
  static const skinTypeOptions = [
    (SkinType.dry, 'Кожа стянута, появляется шелушение', 'Сухая'),
    (SkinType.normal, 'Комфортно, без блеска и стянутости', 'Нормальная'),
    (SkinType.oily, 'Блестит по всему лицу', 'Жирная'),
    (SkinType.combination, 'Блестит только Т-зона', 'Комбинированная'),
    (
      SkinType.sensitive,
      'Появляется покраснение или раздражение',
      'Чувствительная',
    ),
  ];
}

/// Builds the final Beauty Profile: questionnaire (colour + skin questions)
/// plus the optional photo analysis. A skipped photo changes nothing.
class BeautyTestFlow {
  BeautyTestFlow._();

  static MergedBeauty build({
    required ColorTestResult color,
    required SkinType skinType,
    required Set<SkinConcern> concerns,
    VisionAnalysis? vision,
  }) {
    // too many skipped questions: nothing is guessed, the photo fills it in
    final weak = color.isWeak;
    final questionnaire = BeautyProfile.fromLabels(
      skinType: skinType.label,
      skinTone: weak ? null : color.skinTone,
      undertone: weak ? null : color.undertone,
      colorType: weak ? null : color.colorType,
      concerns: [for (final c in concerns) c.label],
    );
    return BeautyProfileMerger.merge(questionnaire, vision);
  }
}
