/// Where the Ollama server lives and which models to use.
///
/// Ollama normally runs on ANOTHER machine (same Wi-Fi/LAN), so there is no
/// localhost default: on a phone `localhost` is the phone itself.
///
/// Values come from `--dart-define` (build time) and can be overridden in the
/// app (Settings -> AI assistant), the override is stored in SQLite.
///
///     flutter run \
///       --dart-define=OLLAMA_BASE_URL=http://192.168.1.50:11434 \
///       --dart-define=OLLAMA_TEXT_MODEL=llama3.2 \
///       --dart-define=OLLAMA_VISION_MODEL=llava
class AiConfig {
  const AiConfig({
    required this.baseUrl,
    required this.textModel,
    required this.visionModel,
  });

  static const defaultBaseUrl = String.fromEnvironment('OLLAMA_BASE_URL');
  static const defaultTextModel = String.fromEnvironment(
    'OLLAMA_TEXT_MODEL',
    defaultValue: 'llama3.2',
  );
  static const defaultVisionModel = String.fromEnvironment(
    'OLLAMA_VISION_MODEL',
    defaultValue: 'llava',
  );

  factory AiConfig.fromEnvironment() => const AiConfig(
    baseUrl: defaultBaseUrl,
    textModel: defaultTextModel,
    visionModel: defaultVisionModel,
  );

  final String baseUrl;
  final String textModel;
  final String visionModel;

  bool get isConfigured => baseUrl.trim().isNotEmpty;

  /// Normalized server URI, or null when empty/invalid.
  Uri? get baseUri {
    var raw = baseUrl.trim();
    if (raw.isEmpty) return null;
    if (!raw.contains('://')) raw = 'http://$raw';
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) return null;
    return uri.replace(path: uri.path.replaceAll(RegExp(r'/+$'), ''));
  }

  /// Host (and port) for display in Settings.
  String get displayHost {
    final u = baseUri;
    if (u == null) return '';
    return u.hasPort ? '${u.host}:${u.port}' : u.host;
  }

  AiConfig copyWith({
    String? baseUrl,
    String? textModel,
    String? visionModel,
  }) => AiConfig(
    baseUrl: baseUrl ?? this.baseUrl,
    textModel: textModel ?? this.textModel,
    visionModel: visionModel ?? this.visionModel,
  );
}
