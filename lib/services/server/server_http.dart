import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cosmetix/services/ai/ai_config.dart';
import 'package:cosmetix/services/server/server_exceptions.dart';

/// How often and how long a failed request is repeated.
class RetryPolicy {
  const RetryPolicy({
    this.maxAttempts = 3,
    this.baseDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 8),
  });

  /// Total tries, the first one included.
  final int maxAttempts;
  final Duration baseDelay;

  /// Longest pause (also the longest `Retry-After` that is waited for).
  final Duration maxDelay;

  static const none = RetryPolicy(maxAttempts: 1);

  Duration delayFor(int attempt) {
    final d = baseDelay * (1 << (attempt - 1));
    return d > maxDelay ? maxDelay : d;
  }
}

/// A plain JSON-over-HTTP client for the Cosmetix server (`dart:io`, no extra
/// packages). The address and the shared app token come from the same settings
/// as the AI proxy: it is one server.
///
/// Retries, by what is safe:
///  * `idempotent` requests (GET, PUT, DELETE) are repeated on timeouts,
///    network errors and 502/503/504;
///  * a POST is never repeated after it may have reached the server (it could
///    create the device or the events twice);
///  * 429 means "not processed", so it is waited out for every method, as long
///    as the server asks for no more than [RetryPolicy.maxDelay];
///  * other 4xx are never repeated.
class ServerHttp {
  ServerHttp(
    this._config, {
    this.timeout = const Duration(seconds: 15),
    this.retry = const RetryPolicy(),
    Future<void> Function(Duration)? sleep,
  }) : _sleep = sleep ?? Future<void>.delayed;

  /// Read on every call so a changed address applies at once.
  final AiConfig Function() _config;
  final Duration timeout;
  final RetryPolicy retry;
  final Future<void> Function(Duration) _sleep;

  /// A catalog page is a few hundred KB at most; anything bigger is not ours.
  static const maxResponseBytes = 5 * 1024 * 1024;

  /// Returns the decoded JSON body (`null` for 204).
  Future<Object?> send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? json,
    String? bearer,
    bool idempotent = false,
  }) async {
    final cfg = _config();
    final base = cfg.baseUri;
    if (base == null) {
      throw const ServerUnavailable('The server address is not set');
    }
    final uri = base.replace(
      path: '${base.path}$path',
      queryParameters: query == null || query.isEmpty ? null : query,
    );
    for (var attempt = 1; ; attempt++) {
      final last = attempt >= retry.maxAttempts;
      try {
        final res = await _once(method, uri, json, bearer, cfg.appToken);
        final status = res.status;
        if (status >= 200 && status < 300) return _decode(res, status);
        if (status == 429) {
          final wait = res.retryAfter;
          final tooLong =
              wait != null && Duration(seconds: wait) > retry.maxDelay;
          if (last || tooLong) {
            throw ServerRateLimited(
              _message(res) ?? 'The server is busy, try again later',
              retryAfter: wait,
            );
          }
          await _sleep(
            wait != null ? Duration(seconds: wait) : retry.delayFor(attempt),
          );
          continue;
        }
        if (status == 502 || status == 503 || status == 504) {
          if (idempotent && !last) {
            await _sleep(retry.delayFor(attempt));
            continue;
          }
          throw ServerUnavailable(_message(res) ?? 'The server is unavailable');
        }
        throw _errorFor(res);
      } on TimeoutException {
        if (idempotent && !last) {
          await _sleep(retry.delayFor(attempt));
          continue;
        }
        throw const ServerTimeout('The server did not answer in time');
      } on SocketException catch (e) {
        if (idempotent && !last) {
          await _sleep(retry.delayFor(attempt));
          continue;
        }
        throw ServerUnavailable('Cannot reach the server: ${e.message}');
      } on HandshakeException {
        // a certificate problem does not go away by itself
        throw const ServerUnavailable('Secure connection failed');
      } on HttpException catch (e) {
        if (idempotent && !last) {
          await _sleep(retry.delayFor(attempt));
          continue;
        }
        throw ServerUnavailable('HTTP error: ${e.message}');
      }
    }
  }

  Future<_Raw> _once(
    String method,
    Uri uri,
    Object? json,
    String? bearer,
    String appToken,
  ) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      return await (() async {
        final req = await client.openUrl(method, uri);
        // never follow a redirect: the tokens must not travel to another address
        req.followRedirects = false;
        // no user agent, no device model, no ids: the server learns nothing else
        req.headers.set(HttpHeaders.userAgentHeader, 'cosmetix-app');
        if (appToken.isNotEmpty) req.headers.set('x-app-token', appToken);
        if (bearer != null) {
          req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
        }
        if (json != null) {
          req.headers.contentType = ContentType.json;
          req.write(jsonEncode(json));
        }
        final res = await req.close();
        final bytes = <int>[];
        await for (final chunk in res) {
          bytes.addAll(chunk);
          if (bytes.length > maxResponseBytes) {
            throw const ServerBadResponse('The answer is too large');
          }
        }
        return _Raw(
          res.statusCode,
          utf8.decode(bytes, allowMalformed: true),
          int.tryParse(res.headers.value('retry-after') ?? ''),
        );
      })().timeout(timeout);
    } finally {
      client.close(force: true);
    }
  }

  Object? _decode(_Raw res, int status) {
    if (status == 204 || res.body.isEmpty) return null;
    try {
      return jsonDecode(res.body);
    } catch (_) {
      throw const ServerBadResponse(
        'The server returned something that is not JSON',
      );
    }
  }

  static String? _message(_Raw r) {
    try {
      final d = jsonDecode(r.body);
      if (d is Map &&
          d['message'] is String &&
          (d['message'] as String).isNotEmpty) {
        return d['message'] as String;
      }
    } catch (_) {}
    return null;
  }

  static String? _code(_Raw r) {
    try {
      final d = jsonDecode(r.body);
      if (d is Map && d['error'] is String) return d['error'] as String;
    } catch (_) {}
    return null;
  }

  static ServerException _errorFor(_Raw r) {
    final message = _message(r) ?? 'HTTP ${r.status}';
    if (r.status == 401) return ServerUnauthorized(message);
    if (r.status >= 500) return ServerUnavailable(message);
    return ServerRejected(message, statusCode: r.status, code: _code(r));
  }
}

class _Raw {
  const _Raw(this.status, this.body, this.retryAfter);
  final int status;
  final String body;
  final int? retryAfter;
}
