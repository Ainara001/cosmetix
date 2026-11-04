import 'dart:convert';

import 'package:cosmetix/repositories/settings_repository.dart';

/// One kind of data that may go to the Cosmetix server. Every one is OFF until
/// the user turns it on, and each can be turned off again.
enum ShareScope {
  /// The device gets an anonymous random id and token. No data is sent with it.
  deviceRegistration,

  /// A short list of app events (see `AppEventType`): "app opened", which screen,
  /// which product page. Never search texts, photos or skin analysis results.
  usageEvents,

  /// Year of birth, skin type and skin concerns the user typed in themselves.
  profile,

  /// The reaction diary: which product, a short title, severity 1-5, the date.
  /// Not the free-text notes and never the photos.
  reactions,
}

/// What the user allowed. A consent given under an older [currentVersion] of the
/// data-collection rules counts as no consent: the user is asked again.
class ServerConsent {
  const ServerConsent({
    this.version = currentVersion,
    this.scopes = const {},
    this.givenAt,
  });

  /// Raise this number whenever the rules of what is collected change.
  static const currentVersion = 1;

  static const none = ServerConsent(scopes: {});

  final int version;
  final Set<ShareScope> scopes;
  final DateTime? givenAt;

  bool allows(ShareScope scope) =>
      version == currentVersion && scopes.contains(scope);

  Map<String, Object?> toJson() => {
    'version': version,
    'scopes': [for (final s in scopes) s.name],
    'givenAt': givenAt?.toUtc().toIso8601String(),
  };

  /// Anything unreadable is "no consent", never "consent".
  factory ServerConsent.fromJson(Object? raw) {
    try {
      if (raw is! Map) return none;
      final names = raw['scopes'];
      final version = raw['version'];
      if (names is! List || version is! int) return none;
      final scopes = {
        for (final n in names)
          for (final s in ShareScope.values)
            if (s.name == n) s,
      };
      final at = raw['givenAt'];
      return ServerConsent(
        version: version,
        scopes: scopes,
        givenAt: at is String ? DateTime.tryParse(at) : null,
      );
    } catch (_) {
      return none;
    }
  }
}

/// The anonymous identity the server gave this installation. It is random: it
/// is not derived from the phone, the account or any hardware identifier, and
/// it disappears with the app data.
class DeviceCredentials {
  const DeviceCredentials({required this.userId, required this.token});
  final String userId;

  /// A secret. Never logged, never shown.
  final String token;

  Map<String, Object?> toJson() => {'userId': userId, 'token': token};

  static DeviceCredentials? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['userId'];
    final token = raw['token'];
    if (id is! String || token is! String || id.isEmpty || token.isEmpty) {
      return null;
    }
    return DeviceCredentials(userId: id, token: token);
  }

  @override
  String toString() => 'DeviceCredentials($userId, token: ***)';
}

/// Where the consent and the device credentials are kept between launches.
abstract interface class ServerStateStore {
  Future<ServerConsent> loadConsent();
  Future<void> saveConsent(ServerConsent consent);
  Future<DeviceCredentials?> loadCredentials();

  /// `null` forgets the credentials.
  Future<void> saveCredentials(DeviceCredentials? credentials);
}

/// Keeps both in the app's own SQLite `settings` table (inside the app sandbox,
/// like the AI settings). A later step may move the token to the iOS Keychain
/// by writing another [ServerStateStore].
class SettingsServerStateStore implements ServerStateStore {
  SettingsServerStateStore(this._settings);

  static const consentKey = 'server_consent';
  static const credentialsKey = 'server_device';

  final SettingsRepository _settings;

  Object? _decode(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ServerConsent> loadConsent() async =>
      ServerConsent.fromJson(_decode((await _settings.all())[consentKey]));

  @override
  Future<void> saveConsent(ServerConsent consent) =>
      _settings.set(consentKey, jsonEncode(consent.toJson()));

  @override
  Future<DeviceCredentials?> loadCredentials() async =>
      DeviceCredentials.fromJson(
        _decode((await _settings.all())[credentialsKey]),
      );

  @override
  Future<void> saveCredentials(DeviceCredentials? credentials) => _settings.set(
    credentialsKey,
    credentials == null ? '' : jsonEncode(credentials.toJson()),
  );
}

/// For tests and previews: nothing is written anywhere.
class MemoryServerStateStore implements ServerStateStore {
  ServerConsent consent = ServerConsent.none;
  DeviceCredentials? credentials;

  @override
  Future<ServerConsent> loadConsent() async => consent;

  @override
  Future<void> saveConsent(ServerConsent c) async => consent = c;

  @override
  Future<DeviceCredentials?> loadCredentials() async => credentials;

  @override
  Future<void> saveCredentials(DeviceCredentials? c) async => credentials = c;
}
