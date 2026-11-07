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
    client = AiClient(() => config);
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

  /// What the proxy said about photos in its health check (`null` = not known
  /// yet or an older proxy) and how the AI provider may use what is sent.
  bool? photoAnalysis;
  String? dataUse;

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

  /// Photos may be sent only when the build allows it AND the proxy said so
  /// explicitly. Unknown means no: the photo is never sent "just in case".
  bool get photoAnalysisAllowed =>
      AiConfig.photoAnalysisAtBuild && photoAnalysis == true;

  /// The server (or the build) is known to refuse photos: the photo step is
  /// replaced by an explanation. False while the answer is still unknown.
  bool get photoAnalysisOff =>
      !AiConfig.photoAnalysisAtBuild ||
      (status == AiStatus.online && photoAnalysis != true);

  /// Remember that the proxy refused a photo although the health check had
  /// said yes (the operator switched it off in between).
  void markPhotoDisabled() {
    photoAnalysis = false;
    notifyListeners();
  }

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
    photoAnalysis = null;
    dataUse = null;
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
    photoAnalysis = null;
    dataUse = null;
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
      photoAnalysis = null;
      dataUse = null;
      notifyListeners();
      return;
    }
    status = AiStatus.checking;
    notifyListeners();
    try {
      final h = await client.health();
      mode = h.mode;
      model = h.model;
      photoAnalysis = h.photoAnalysis;
      dataUse = h.dataUse;
      status = AiStatus.online;
      detail = null;
    } on AiException catch (e) {
      status = AiStatus.offline;
      detail = e.message;
      mode = null;
      model = null;
      photoAnalysis = null;
      dataUse = null;
    } catch (e) {
      status = AiStatus.offline;
      detail = 'Unexpected error';
      mode = null;
      model = null;
      photoAnalysis = null;
      dataUse = null;
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
