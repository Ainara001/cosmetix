import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cosmetix/services/ai/ai_config.dart';

/// Base class of everything that can go wrong while talking to the AI proxy.
/// The app never lets these crash a screen: callers fall back or show a
/// message.
sealed class AiException implements Exception {
  const AiException(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Not configured, offline, unreachable, or the API itself is down.
class AiUnavailable extends AiException {
  const AiUnavailable(super.message);
}

class AiTimeout extends AiException {
  const AiTimeout(super.message);
}

/// Too many requests or the daily budget is used up (HTTP 429).
class AiRateLimited extends AiException {
  const AiRateLimited(super.message, {this.retryAfter});

  /// Seconds the proxy asked us to wait, when it said so.
  final int? retryAfter;
}

/// The proxy rejected the request or answered with an error.
class AiServerError extends AiException {
  const AiServerError(super.message, {this.statusCode});
  final int? statusCode;
}

/// The app itself refused to call the remote AI (for example: the Gemini API
/// terms do not allow an app that may be used by people under 18). Nothing was sent.
class AiNotAllowed extends AiException {
  const AiNotAllowed(super.message);
}

/// The model answered, but not with usable data (invalid/incomplete JSON).
class AiBadResponse extends AiException {
  const AiBadResponse(super.message);
}

class AiMessage {
  const AiMessage(this.role, this.content, {this.images = const []});

  final String role; // system | user | assistant
  final String content;

  /// base64 images (photo analysis). Never logged.
  final List<String> images;
}

class AiReply {
  const AiReply(this.text, {this.mock = false});

  final String text;

  /// True when the proxy has no AI key and answered in test mode.
  final bool mock;
}

class AiHealth {
  const AiHealth({required this.mode, this.model});

  /// `gemini` or `claude` (real answers) or `mock` (test mode, answers are marked).
  final String mode;
  final String? model;

  bool get isMock => mode == 'mock';
}

/// Client of the Cosmetix AI proxy (see `server/`). The proxy owns the AI
/// API key; this app never sees one. Plain `dart:io`, no extra packages.
class AiClient {
  AiClient(this._config, {this.mayUseRemoteAi});

  /// Read on every call so Settings changes apply immediately.
  final AiConfig Function() _config;

  /// The one gate every request that carries user content goes through
  /// (chat, photo, AI ranking, product classification). When it says no,
  /// [chat] throws [AiNotAllowed] BEFORE anything is sent. The health check
  /// carries no user content and is not gated. `null` = no gate (tests).
  final bool Function()? mayUseRemoteAi;

  static const healthTimeout = Duration(seconds: 4);
  static const chatTimeout = Duration(seconds: 60);
  static const visionTimeout = Duration(seconds: 90);

  /// Messages longer than this are cut before sending (cost control; the
  /// proxy enforces its own, stricter-than-needed limits as well).
  static const maxMessageChars = 9000;

  /// GET /health: is the proxy reachable and is it talking to a real model.
  Future<AiHealth> health({Duration timeout = healthTimeout}) async {
    final res = await _request('GET', '/health', null, timeout);
    final data = _decode(res.body);
    final mode = data['mode'];
    if (mode is! String) throw const AiBadResponse('Not a Cosmetix AI proxy');
    final model = data['model'];
    return AiHealth(mode: mode, model: model is String ? model : null);
  }

  /// POST /v1/chat. System messages become the proxy's `system` field.
  /// [json] asks for a structured (JSON) answer.
  Future<AiReply> chat({
    required List<AiMessage> messages,
    bool json = false,
    Duration timeout = chatTimeout,
    double? temperature,
    int? maxTokens,
  }) async {
    if (mayUseRemoteAi != null && !mayUseRemoteAi!()) {
      throw const AiNotAllowed('The remote AI is not available for this user');
    }
    final system = messages
        .where((m) => m.role == 'system')
        .map((m) => _cut(m.content))
        .join('\n\n');
    final turns = [
      for (final m in messages)
        if (m.role != 'system')
          {
            'role': m.role,
            'content': _cut(m.content),
            if (m.images.isNotEmpty) 'images': m.images,
          },
    ];
    final res = await _request('POST', '/v1/chat', {
      if (system.isNotEmpty) 'system': system,
      'messages': turns,
      if (json) 'json': true,
      'temperature': ?temperature,
      'maxTokens': ?maxTokens,
    }, timeout);
    final data = _decode(res.body);
    final text = data['text'];
    if (text is! String || text.trim().isEmpty) {
      throw const AiBadResponse('Empty answer from the AI');
    }
    return AiReply(text, mock: data['mock'] == true);
  }

  static String _cut(String s) =>
      s.length <= maxMessageChars ? s : s.substring(0, maxMessageChars);

  Map<String, Object?> _decode(String body) {
    try {
      final v = jsonDecode(body);
      if (v is Map<String, Object?>) return v;
    } catch (_) {}
    throw const AiBadResponse('The server returned something that is not JSON');
  }

  Future<({int status, String body, int? retryAfter})> _request(
    String method,
    String path,
    Map<String, Object?>? payload,
    Duration timeout,
  ) async {
    final cfg = _config();
    final base = cfg.baseUri;
    if (base == null) {
      throw const AiUnavailable('The AI server address is not set');
    }
    final uri = base.replace(path: '${base.path}$path');
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final res = await _send(
        client,
        method,
        uri,
        payload,
        cfg.appToken,
      ).timeout(timeout);
      if (res.status != 200) throw _errorFor(res);
      return res;
    } on TimeoutException {
      throw const AiTimeout('The AI server did not answer in time');
    } on SocketException catch (e) {
      throw AiUnavailable('Cannot reach the AI server: ${e.message}');
    } on HttpException catch (e) {
      throw AiUnavailable('HTTP error: ${e.message}');
    } on HandshakeException {
      throw const AiUnavailable('Secure connection failed');
    } finally {
      client.close(force: true);
    }
  }

  Future<({int status, String body, int? retryAfter})> _send(
    HttpClient client,
    String method,
    Uri uri,
    Map<String, Object?>? payload,
    String appToken,
  ) async {
    final req = await client.openUrl(method, uri);
    if (appToken.isNotEmpty) req.headers.set('x-app-token', appToken);
    if (payload != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(payload));
    }
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    return (
      status: res.statusCode,
      body: text,
      retryAfter: int.tryParse(res.headers.value('retry-after') ?? ''),
    );
  }

  /// Maps the proxy's JSON error to an [AiException].
  static AiException _errorFor(({int status, String body, int? retryAfter}) r) {
    var code = '';
    var detail = '';
    try {
      final d = jsonDecode(r.body);
      if (d is Map) {
        code = '${d['error'] ?? ''}';
        detail = '${d['message'] ?? ''}';
      }
    } catch (_) {}
    final message = detail.isEmpty ? 'HTTP ${r.status}' : detail;
    switch (r.status) {
      case 429:
        return AiRateLimited(message, retryAfter: r.retryAfter);
      case 504:
        return AiTimeout(message);
      case 503:
        return AiUnavailable(message);
      default:
        return AiServerError(
          code.isEmpty ? message : '$code: $message',
          statusCode: r.status,
        );
    }
  }
}
