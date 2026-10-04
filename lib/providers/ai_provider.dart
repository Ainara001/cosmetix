import 'package:flutter/foundation.dart';

import 'package:cosmetix/repositories/settings_repository.dart';
import 'package:cosmetix/services/ai/ai_config.dart';
import 'package:cosmetix/services/ai/ollama_client.dart';

enum AiStatus { unknown, checking, online, offline }

/// Ollama connection settings (server address, models) and its status.
///
/// The app works fully without AI: only the photo analysis, the chat and the
/// AI-refined ranking need it.
class AiProvider extends ChangeNotifier {
  AiProvider(this._repo, {AiConfig? initial})
    : config = initial ?? AiConfig.fromEnvironment() {
    client = OllamaClient(() => config);
  }

  final SettingsRepository _repo;
  late final OllamaClient client;

  AiConfig config;
  AiStatus status = AiStatus.unknown;

  /// Human-readable reason when offline (not localized: shown as a detail).
  String? detail;
  List<String> installedModels = const [];

  static const _kUrl = 'ai_base_url';
  static const _kText = 'ai_text_model';
  static const _kVision = 'ai_vision_model';

  bool get isConfigured => config.isConfigured;
  bool get isOnline => status == AiStatus.online;
  bool get textModelInstalled =>
      installedModels.isEmpty || _has(config.textModel);
  bool get visionModelInstalled =>
      installedModels.isEmpty || _has(config.visionModel);

  bool _has(String m) => OllamaHealth(installedModels).hasModel(m);

  /// Applies values saved in Settings on top of the build-time defaults.
  Future<void> load() async {
    try {
      final saved = await _repo.all();
      config = AiConfig(
        baseUrl: saved[_kUrl] ?? config.baseUrl,
        textModel: saved[_kText] ?? config.textModel,
        visionModel: saved[_kVision] ?? config.visionModel,
      );
    } catch (e) {
      debugPrint('ai settings load failed: $e');
    }
    notifyListeners();
  }

  Future<void> update({
    String? baseUrl,
    String? textModel,
    String? visionModel,
  }) async {
    config = config.copyWith(
      baseUrl: baseUrl?.trim(),
      textModel: textModel?.trim(),
      visionModel: visionModel?.trim(),
    );
    status = AiStatus.unknown;
    notifyListeners();
    if (baseUrl != null) await _repo.set(_kUrl, config.baseUrl);
    if (textModel != null) await _repo.set(_kText, config.textModel);
    if (visionModel != null) await _repo.set(_kVision, config.visionModel);
  }

  /// Short health check. Never throws.
  Future<void> testConnection() async {
    if (!isConfigured) {
      status = AiStatus.offline;
      detail = null;
      installedModels = const [];
      notifyListeners();
      return;
    }
    status = AiStatus.checking;
    notifyListeners();
    try {
      final h = await client.health();
      installedModels = h.models;
      status = AiStatus.online;
      detail = null;
    } on AiException catch (e) {
      status = AiStatus.offline;
      detail = e.message;
      installedModels = const [];
    } catch (e) {
      status = AiStatus.offline;
      detail = 'Unexpected error';
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
