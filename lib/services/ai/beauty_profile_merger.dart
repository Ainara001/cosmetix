import 'package:cosmetix/core/beauty/beauty_codes.dart';
import 'package:cosmetix/models/ai_models.dart';
import 'package:cosmetix/models/beauty_profile.dart';

class MergedBeauty {
  const MergedBeauty({
    required this.profile,
    this.vision,
    this.photoUsed = false,
  });

  final BeautyProfile profile;
  final VisionAnalysis? vision;

  /// True when a valid, confident photo analysis took part.
  final bool photoUsed;
}

/// questionnaire + optional photo analysis = final Beauty Profile.
///
/// The questionnaire always wins. The photo can only fill a gap: when the
/// questionnaire could not decide the undertone ("neutral") and the photo
/// analysis is confident, its undertone is used.
class BeautyProfileMerger {
  BeautyProfileMerger._();

  static const minConfidence = 0.6;

  static MergedBeauty merge(
    BeautyProfile questionnaire,
    VisionAnalysis? vision,
  ) {
    if (vision == null || vision.confidence < minConfidence) {
      return MergedBeauty(profile: questionnaire, vision: vision);
    }
    var undertone = questionnaire.undertone;
    if ((undertone == null || undertone == Undertone.neutral) &&
        vision.undertone != null &&
        vision.undertone != Undertone.neutral) {
      undertone = vision.undertone;
    }
    return MergedBeauty(
      profile: BeautyProfile(
        skinType: questionnaire.skinType,
        skinTone: questionnaire.skinTone ?? vision.skinTone,
        undertone: undertone,
        colorType: questionnaire.colorType ?? vision.colorType,
        concerns: questionnaire.concerns,
        source: BeautySource.questionnairePhoto,
        confidence: vision.confidence,
      ),
      vision: vision,
      photoUsed: true,
    );
  }
}
