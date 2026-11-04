import 'package:cosmetix/models/app_user.dart';
import 'package:cosmetix/models/safety_models.dart';

/// What of the profile may go to the server, and nothing else.
///
/// Sent: year of birth, skin type, skin concerns.
/// NEVER sent: name, e-mail, phone, city, avatar, anything from the face or skin
/// analysis (colour type, undertone, skin tone, confidence), preferences,
/// bonus points. The skin type and concerns are sent only when the user gave
/// them in the questionnaire; when a photo analysis took part they are left out.
///
/// It mirrors the local state: a field that is empty here is sent as `null`,
/// which clears it on the server (so removing the year of birth in the app
/// removes it there too).
class ProfileSyncPayload {
  const ProfileSyncPayload({
    this.birthYear,
    this.skinType,
    this.skinConcerns = const [],
  });

  final int? birthYear;
  final String? skinType;
  final List<String> skinConcerns;

  factory ProfileSyncPayload.fromUser(AppUser u, {DateTime? now}) {
    final year = (now ?? DateTime.now()).year;
    final by = u.birthYear;
    final byOk = by != null && by >= 1900 && by <= year;
    final typed = u.beautySource == 'questionnaire';
    return ProfileSyncPayload(
      birthYear: byOk ? by : null,
      skinType: typed && u.skinType.trim().isNotEmpty
          ? _cut(u.skinType, 80)
          : null,
      skinConcerns: typed
          ? [
              for (final c in u.skinConcerns.take(10))
                if (c.trim().isNotEmpty) _cut(c, 80),
            ]
          : const [],
    );
  }

  Map<String, Object?> toJson() => {
    'birthYear': birthYear,
    'skinType': skinType,
    'skinConcerns': skinConcerns,
  };

  static String _cut(String s, int max) {
    final t = s.trim();
    return t.length <= max ? t : t.substring(0, max);
  }
}

/// One diary entry as the server stores it.
///
/// Sent: product, a short title, severity 1-5, the date.
/// NEVER sent: the free-text notes (they may hold anything), the photo, the
/// product's name or picture.
class ReactionSyncPayload {
  const ReactionSyncPayload({
    required this.clientId,
    required this.productId,
    required this.title,
    required this.severity,
    required this.date,
  });

  /// The id of the entry in the app's own database: the server uses it to
  /// recognise the same entry on every repeat, so syncing twice is harmless.
  final String clientId;
  final int productId;
  final String title;
  final int severity;

  /// `YYYY-MM-DD`, the day on the phone.
  final String date;

  /// Null when the entry cannot be sent as it is (empty title, severity out of
  /// 1-5): it is skipped, never "fixed" with invented values.
  static ReactionSyncPayload? tryFrom(Reaction r) {
    final title = r.title.trim();
    if (title.isEmpty || r.severity < 1 || r.severity > 5 || r.productId < 1) {
      return null;
    }
    String two(int n) => n.toString().padLeft(2, '0');
    return ReactionSyncPayload(
      clientId: '${r.id}',
      productId: r.productId,
      title: title.length <= 200 ? title : title.substring(0, 200),
      severity: r.severity,
      date:
          '${r.date.year.toString().padLeft(4, '0')}-${two(r.date.month)}-${two(r.date.day)}',
    );
  }

  Map<String, Object?> toJson() => {
    'productId': productId,
    'title': title,
    'severity': severity,
    'date': date,
  };
}
