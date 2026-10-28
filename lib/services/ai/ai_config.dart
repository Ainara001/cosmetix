/// Where the Cosmetix AI proxy lives (see `server/`).
///
/// The proxy talks to the AI provider (Gemini or Claude) and owns the API key, so the app only
/// needs an address (and, optionally, a shared token). There is no
/// `localhost` default: on a phone `localhost` is the phone itself.
///
/// Values come from `--dart-define` (build time) and can be overridden in the
/// app (Settings -> AI assistant), the override is stored in SQLite.
///
///     flutter run \
///       --dart-define=AI_BASE_URL=http://192.168.1.50:8787 \
///       --dart-define=AI_APP_TOKEN=optional-shared-token
class AiConfig {
  const AiConfig({required this.baseUrl, this.appToken = ''});

  /// Port of the proxy when only a bare LAN address is typed.
  static const defaultPort = 8787;
  static const defaultBaseUrl = String.fromEnvironment('AI_BASE_URL');
  static const defaultAppToken = String.fromEnvironment('AI_APP_TOKEN');

  factory AiConfig.fromEnvironment() =>
      const AiConfig(baseUrl: defaultBaseUrl, appToken: defaultAppToken);

  final String baseUrl;

  /// Optional shared secret for the proxy's `APP_TOKEN` (sent as a header).
  final String appToken;

  bool get isConfigured => baseUrl.trim().isNotEmpty;

  /// Normalized server URI, or null when empty/invalid.
  Uri? get baseUri {
    var raw = baseUrl.trim();
    if (raw.isEmpty) return null;
    if (!raw.contains('://')) raw = 'http://$raw';
    var uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) return null;
    // a bare LAN address (192.168.1.50) means the proxy's default port
    if (uri.scheme == 'http' &&
        !uri.hasPort &&
        RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(uri.host)) {
      uri = uri.replace(port: defaultPort);
    }
    return uri.replace(path: uri.path.replaceAll(RegExp(r'/+$'), ''));
  }

  /// Host (and port) for display in Settings.
  String get displayHost {
    final u = baseUri;
    if (u == null) return '';
    return u.hasPort ? '${u.host}:${u.port}' : u.host;
  }

  AiConfig copyWith({String? baseUrl, String? appToken}) => AiConfig(
    baseUrl: baseUrl ?? this.baseUrl,
    appToken: appToken ?? this.appToken,
  );
}
