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

  static MergedBeauty merge(
    BeautyProfile questionnaire,
    VisionAnalysis? vision,
  ) {
    // no decision by the model's own number: whether a photo is good enough
    // was decided on the phone (PhotoCheck) before it was sent at all
    if (vision == null) {
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
