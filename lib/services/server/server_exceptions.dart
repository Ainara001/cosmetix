import 'package:cosmetix/services/server/server_consent.dart';

/// Everything that can go wrong while talking to the Cosmetix server (catalog,
/// profile, events). The app never lets these crash a screen: it works offline
/// from its own SQLite database, callers catch these and carry on.
sealed class ServerException implements Exception {
  const ServerException(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The address is not set, the phone is offline, the server is down or keeps
/// answering 5xx.
class ServerUnavailable extends ServerException {
  const ServerUnavailable(super.message);
}

class ServerTimeout extends ServerException {
  const ServerTimeout(super.message);
}

/// HTTP 429 (and the retries did not help).
class ServerRateLimited extends ServerException {
  const ServerRateLimited(super.message, {this.retryAfter});

  /// Seconds the server asked us to wait, when it said so.
  final int? retryAfter;
}

/// The device token (or the shared app token) was refused (HTTP 401). The
/// stored device credentials are dropped when this happens.
class ServerUnauthorized extends ServerException {
  const ServerUnauthorized(super.message);
}

/// The server refused the request (other 4xx): a bug or a data problem, not
/// something a retry fixes.
class ServerRejected extends ServerException {
  const ServerRejected(super.message, {required this.statusCode, this.code});
  final int statusCode;

  /// The server's machine-readable `error` (for example `bad_request`).
  final String? code;
}

/// The server answered, but not with what the API promises.
class ServerBadResponse extends ServerException {
  const ServerBadResponse(super.message);
}

/// The user has not allowed this kind of data sharing (or allowed it under
/// older rules). Nothing was sent.
class ConsentRequired extends ServerException {
  const ConsentRequired(this.scope)
    : super('The user has not allowed this kind of data sharing');
  final ShareScope scope;
}

/// The call needs a registered device, but there is none yet.
class DeviceNotRegistered extends ServerException {
  const DeviceNotRegistered() : super('The device is not registered');
}
