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
/// The questionnaire wins. The photo fills the gaps: a skipped question
/// leaves a value empty and a confident photo analysis provides it; a
/// "neutral" undertone is replaced by the photo's warm/cool.
class BeautyProfileMerger {
  BeautyProfileMerger._();

  /// The model's own "I cannot judge this photo" brake. It is not shown, not
  /// stored and never makes a photo count MORE: it can only make a photo count
  /// for nothing. The number is the model's self-report, not a measurement
  /// (on bad photos it still says 0.6-0.9), so it is no proof that a photo is
  /// good; the proper check is local and happens before sending.
  static const minConfidence = 0.6;

  static MergedBeauty merge(
    BeautyProfile questionnaire,
    VisionAnalysis? vision,
  ) {
    if (vision == null || vision.confidence < minConfidence) {
      return MergedBeauty(profile: questionnaire, vision: vision);
    }
    var undertone = questionnaire.undertone;
    if (undertone == null) {
      // the questionnaire did not decide (skipped): the photo decides
      undertone = vision.undertone;
    } else if (undertone == Undertone.neutral &&
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
      ),
      vision: vision,
      photoUsed: true,
    );
  }
}
