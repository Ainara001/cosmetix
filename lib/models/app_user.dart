import 'package:cosmetix/core/utils/app_paths.dart';
import 'package:cosmetix/models/beauty_profile.dart';
import 'package:cosmetix/services/age_safety.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.phone = '',
    this.city = '',
    this.skinType = 'Нормальная',
    this.skinTone = 'Светлый',
    this.undertone = 'Нейтральный',
    this.colorType = '',
    this.skinConcerns = const [],
    this.bonusPoints = 0,
    this.visits = 0,
    this.avatarColor = 0xFFD4A0AC,
    this.avatarPath,
    this.beautySource = 'questionnaire',
    this.beautyConfidence,
    this.beautyAnalyzedAt,
    this.preferences = const {},
    this.recoUseHistory = false,
    this.birthYear,
    this.beautyCompletedAt,
  });

  final int id;
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final String city;
  final String skinType;
  final String skinTone;
  final String undertone;
  final String colorType;
  final List<String> skinConcerns;
  final int bonusPoints;
  final int visits;
  final int avatarColor;

  /// Persistent avatar photo (application documents directory), if any.
  final String? avatarPath;

  /// 'questionnaire' or 'questionnaire_photo'.
  final String beautySource;
  final double? beautyConfidence;
  final int? beautyAnalyzedAt;

  /// Personal preferences (codes of `Preferences`).
  final Set<String> preferences;

  /// The user allowed the recommendations to take their reactions and
  /// cosmetic bag into account.
  final bool recoUseHistory;

  /// Year of birth (optional): limits strong actives for children.
  final int? birthYear;

  /// When the skin questions were last answered (ms since epoch).
  final int? beautyCompletedAt;

  /// The careful age (see `AgeSafety`), null when the year is not given.
  int? get age => AgeSafety.ageFromBirthYear(birthYear);

  /// Time to ask again how the skin feels after washing: it changes with the
  /// season and the care.
  bool skinCheckDue({DateTime? now, int days = 30}) {
    if (!hasBeautyProfile) return false;
    final at = beautyCompletedAt;
    if (at == null) return true;
    final ms = (now ?? DateTime.now()).millisecondsSinceEpoch - at;
    return ms > days * Duration.millisecondsPerDay;
  }

  String get fullName => '$lastName $firstName'.trim();

  BeautyProfile get beautyProfile => BeautyProfile.fromLabels(
    skinType: skinType,
    skinTone: skinTone,
    undertone: undertone,
    colorType: colorType,
    concerns: skinConcerns,
    source: beautySource,
    confidence: beautyConfidence,
    preferences: preferences,
    age: age,
  );

  bool get hasBeautyProfile => colorType.isNotEmpty;

  factory AppUser.fromMap(Map<String, Object?> m) {
    final concerns = (m['skin_concerns'] as String? ?? '')
        .split('|')
        .where((e) => e.isNotEmpty)
        .toList();
    return AppUser(
      id: m['id'] as int,
      firstName: m['first_name'] as String? ?? '',
      lastName: m['last_name'] as String? ?? '',
      email: m['email'] as String? ?? '',
      phone: m['phone'] as String? ?? '',
      city: m['city'] as String? ?? '',
      skinType: m['skin_type'] as String? ?? 'Нормальная',
      skinTone: m['skin_tone'] as String? ?? 'Светлый',
      undertone: m['undertone'] as String? ?? 'Нейтральный',
      colorType: m['color_type'] as String? ?? '',
      skinConcerns: concerns,
      bonusPoints: m['bonus_points'] as int? ?? 0,
      visits: m['visits'] as int? ?? 0,
      avatarColor: m['avatar_color'] as int? ?? 0xFFD4A0AC,
      avatarPath: AppPaths.resolve(m['avatar_path'] as String?),
      beautySource: m['beauty_source'] as String? ?? 'questionnaire',
      beautyConfidence: (m['beauty_confidence'] as num?)?.toDouble(),
      beautyAnalyzedAt: m['beauty_analyzed_at'] as int?,
      preferences: Preferences.parse(m['preferences'] as String?),
      recoUseHistory: (m['reco_use_history'] as int? ?? 0) == 1,
      birthYear: m['birth_year'] as int?,
      beautyCompletedAt: m['beauty_completed_at'] as int?,
    );
  }
}
