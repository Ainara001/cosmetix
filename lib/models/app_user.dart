import 'package:cosmetix/models/beauty_profile.dart';

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

  String get fullName => '$lastName $firstName'.trim();

  BeautyProfile get beautyProfile => BeautyProfile.fromLabels(
    skinType: skinType,
    skinTone: skinTone,
    undertone: undertone,
    colorType: colorType,
    concerns: skinConcerns,
    source: beautySource,
    confidence: beautyConfidence,
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
      avatarPath: m['avatar_path'] as String?,
      beautySource: m['beauty_source'] as String? ?? 'questionnaire',
      beautyConfidence: (m['beauty_confidence'] as num?)?.toDouble(),
      beautyAnalyzedAt: m['beauty_analyzed_at'] as int?,
    );
  }
}
