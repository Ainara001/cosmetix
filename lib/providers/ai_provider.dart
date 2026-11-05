import 'package:flutter/foundation.dart';

import 'package:cosmetix/repositories/settings_repository.dart';
import 'package:cosmetix/services/ai/ai_client.dart';
import 'package:cosmetix/services/ai/ai_config.dart';

enum AiStatus { unknown, checking, online, offline }

/// Connection to the Cosmetix AI proxy (address, status, test/real mode) and
/// the user's consent about what may be sent to the AI.
///
/// The app works fully without AI: only the photo analysis, the chat and the
/// AI-refined ranking need it.
class AiProvider extends ChangeNotifier {
  AiProvider(this._repo, {AiConfig? initial})
    : config = initial ?? AiConfig.fromEnvironment() {
    client = AiClient(() => config, mayUseRemoteAi: () => ageAllowed);
  }

  final SettingsRepository _repo;
  late final AiClient client;

  AiConfig config;
  AiStatus status = AiStatus.unknown;

  /// Human-readable reason when offline (not localized: shown as a detail).
  String? detail;

  /// `gemini`, `claude` or `mock` once the proxy answered the health check.
  String? mode;
  String? model;

  // ---- age: the Gemini API terms ----

  /// The Gemini API terms do not allow an application that is directed to, or
  /// likely to be accessed by, people under 18. Cosmetix has no age check at
  /// sign-up, so the remote AI (chat, photo, AI ranking, classification) is
  /// available only to a user who has stated a year of birth that makes them
  /// at least [minAge]. The age is the careful one (`AgeSafety.ageFromBirthYear`
  /// rounds down), so a user is never let in a year early.
  static const minAge = 18;

  /// Where the user's age comes from. Wired in `app.dart`. Not set = nobody is
  /// allowed (the safe default).
  int? Function()? ageSource;

  int? get userAge => ageSource?.call();

  /// False for a minor and for a user whose age is not known.
  bool get ageAllowed {
    final a = userAge;
    return a != null && a >= minAge;
  }

  /// The user has not given a year of birth (as opposed to being too young).
  bool get ageUnknown => userAge == null;

  /// Tells the screens that the age (the profile) changed.
  void ageChanged() => notifyListeners();

  // ---- consent: nothing personal leaves the phone without it ----

  /// The Beauty profile and the blacklist may be sent to the AI as context.
  bool shareProfile = false;

  /// A face photo may be sent to the AI (Beauty Test photo step).
  bool sharePhotos = false;

  /// The user has been asked about [shareProfile] once (first chat message).
  bool profileAsked = false;

  static const _kUrl = 'ai_base_url';
  static const _kToken = 'ai_app_token';
  static const _kShareProfile = 'ai_share_profile';
  static const _kSharePhotos = 'ai_share_photos';
  static const _kProfileAsked = 'ai_profile_asked';

  bool get isConfigured => config.isConfigured;
  bool get isOnline => status == AiStatus.online;

  /// True when the proxy has no AI key and answers are test data.
  bool get isMock => mode == 'mock';

  /// Applies values saved in Settings on top of the build-time defaults.
  Future<void> load() async {
    try {
      final saved = await _repo.all();
      var url = saved[_kUrl] ?? config.baseUrl;
      // an address saved by the old Ollama build points to the wrong service
      if (url.contains(':11434')) url = AiConfig.defaultBaseUrl;
      config = AiConfig(
        baseUrl: url,
        appToken: saved[_kToken] ?? config.appToken,
      );
      shareProfile = saved[_kShareProfile] == '1';
      sharePhotos = saved[_kSharePhotos] == '1';
      profileAsked = saved[_kProfileAsked] == '1';
    } catch (e) {
      debugPrint('ai settings load failed: $e');
    }
    notifyListeners();
  }

  /// Forgets the saved server and consent (after the demo data reset).
  void resetToDefaults() {
    config = AiConfig.fromEnvironment();
    status = AiStatus.unknown;
    detail = null;
    mode = null;
    model = null;
    shareProfile = false;
    sharePhotos = false;
    profileAsked = false;
    notifyListeners();
  }

  Future<void> update({String? baseUrl, String? appToken}) async {
    config = config.copyWith(
      baseUrl: baseUrl?.trim(),
      appToken: appToken?.trim(),
    );
    status = AiStatus.unknown;
    mode = null;
    model = null;
    notifyListeners();
    if (baseUrl != null) await _repo.set(_kUrl, config.baseUrl);
    if (appToken != null) await _repo.set(_kToken, config.appToken);
  }

  Future<void> setShareProfile(bool value) async {
    shareProfile = value;
    profileAsked = true;
    notifyListeners();
    await _repo.set(_kShareProfile, value ? '1' : '0');
    await _repo.set(_kProfileAsked, '1');
  }

  Future<void> setSharePhotos(bool value) async {
    sharePhotos = value;
    notifyListeners();
    await _repo.set(_kSharePhotos, value ? '1' : '0');
  }

  /// Short health check. Never throws.
  Future<void> testConnection() async {
    if (!isConfigured) {
      status = AiStatus.offline;
      detail = null;
      mode = null;
      model = null;
      notifyListeners();
      return;
    }
    status = AiStatus.checking;
    notifyListeners();
    try {
      final h = await client.health();
      mode = h.mode;
      model = h.model;
      status = AiStatus.online;
      detail = null;
    } on AiException catch (e) {
      status = AiStatus.offline;
      detail = e.message;
      mode = null;
      model = null;
    } catch (e) {
      status = AiStatus.offline;
      detail = 'Unexpected error';
      mode = null;
      model = null;
    }
    notifyListeners();
  }

  /// Call after a request failed so the UI shows the offline state.
  void markOffline(String reason) {
    status = AiStatus.offline;
    detail = reason;
    notifyListeners();
  }
}
