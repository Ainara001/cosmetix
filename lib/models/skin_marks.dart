import 'package:cosmetix/core/beauty/beauty_codes.dart';
import 'package:cosmetix/core/face/face_zones.dart';

/// What a person can mark on a zone of their face. These are THEIR
/// observations, not a diagnosis and not an automatic classification.
enum SkinFeature {
  acne('acne', 'Высыпания (акне)'),
  comedones('comedones', 'Чёрные точки, комедоны'),
  redness('redness', 'Покраснения'),
  postAcne('post_acne', 'Следы после высыпаний'),
  pigmentation('pigmentation', 'Пигментные пятна'),
  scars('scars', 'Рубцы'),
  pores('pores', 'Заметные поры'),
  texture('texture', 'Неровная текстура');

  const SkinFeature(this.code, this.label);
  final String code;
  final String label;

  static SkinFeature? fromCode(String? c) {
    for (final f in values) {
      if (f.code == c) return f;
    }
    return null;
  }

  /// The skin concerns of the profile this mark supports. Scars, pores and
  /// texture have no concern of their own: they are kept, not mapped.
  Set<SkinConcern> get concerns => switch (this) {
    acne || comedones => {SkinConcern.acne},
    postAcne => {SkinConcern.acne, SkinConcern.pigmentation},
    pigmentation => {SkinConcern.pigmentation},
    redness => {SkinConcern.sensitivity},
    scars || pores || texture => const {},
  };
}

/// One mark: a feature the person sees on one zone.
class SkinZoneMark {
  const SkinZoneMark(this.zone, this.feature);
  final FaceZone zone;
  final SkinFeature feature;

  @override
  bool operator ==(Object other) =>
      other is SkinZoneMark && other.zone == zone && other.feature == feature;

  @override
  int get hashCode => Object.hash(zone, feature);

  @override
  String toString() => '${zone.code}:${feature.code}';
}

/// The person's current marks.
class SkinMarks {
  const SkinMarks(this.marks, {this.markedAt});

  static const empty = SkinMarks({});

  final Set<SkinZoneMark> marks;
  final DateTime? markedAt;

  bool get isEmpty => marks.isEmpty;

  Set<SkinFeature> on(FaceZone z) => {
    for (final m in marks)
      if (m.zone == z) m.feature,
  };

  /// The profile concerns the marks support (for the care selection).
  Set<SkinConcern> get concerns => {
    for (final m in marks) ...m.feature.concerns,
  };

  /// Scars are for a dermatologist: the app does not pick care for them.
  bool get suggestsDermatologist =>
      marks.any((m) => m.feature == SkinFeature.scars);
}
