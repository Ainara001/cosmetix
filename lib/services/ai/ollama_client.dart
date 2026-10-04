import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cosmetix/services/ai/ai_config.dart';

/// Base class of everything that can go wrong while talking to Ollama. The
/// app never lets these crash a screen: callers fall back or show a message.
sealed class AiException implements Exception {
  const AiException(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Not configured, offline, unreachable.
class AiUnavailable extends AiException {
  const AiUnavailable(super.message);
}

class AiTimeout extends AiException {
  const AiTimeout(super.message);
}

/// The server answered with an error (for example the model is not installed).
class AiServerError extends AiException {
  const AiServerError(super.message, {this.statusCode});
  final int? statusCode;
}

/// The model answered, but not with usable data (invalid/incomplete JSON).
class AiBadResponse extends AiException {
  const AiBadResponse(super.message);
}

class OllamaMessage {
  const OllamaMessage(this.role, this.content, {this.images = const []});

  final String role; // system | user | assistant
  final String content;

  /// base64 images (vision models). Never logged.
  final List<String> images;

  Map<String, Object?> toJson() => {
    'role': role,
    'content': content,
    if (images.isNotEmpty) 'images': images,
  };
}

class OllamaHealth {
  const OllamaHealth(this.models);
  final List<String> models;

  bool hasModel(String name) {
    final base = name.split(':').first;
    return models.any((m) => m == name || m.split(':').first == base);
  }
}

/// Minimal Ollama HTTP client (dart:io, no extra packages).
class OllamaClient {
  OllamaClient(this._config);

  /// Read on every call so Settings changes apply immediately.
  final AiConfig Function() _config;

  static const healthTimeout = Duration(seconds: 4);
  static const chatTimeout = Duration(seconds: 60);
  static const visionTimeout = Duration(seconds: 120);

  /// GET /api/tags: is the server reachable and which models are installed.
  Future<OllamaHealth> health({Duration timeout = healthTimeout}) async {
    final body = await _request('GET', '/api/tags', null, timeout);
    final data = _decode(body);
    final models = data['models'];
    return OllamaHealth([
      if (models is List)
        for (final m in models)
          if (m is Map && m['name'] is String) m['name'] as String,
    ]);
  }

  /// POST /api/chat (non-streaming). Returns the assistant text.
  /// [json] asks the model for JSON output (structured answers).
  Future<String> chat({
    required String model,
    required List<OllamaMessage> messages,
    bool json = false,
    Duration timeout = chatTimeout,
    double? temperature,
  }) async {
    final body = await _request('POST', '/api/chat', {
      'model': model,
      'messages': [for (final m in messages) m.toJson()],
      'stream': false,
      if (json) 'format': 'json',
      if (temperature != null) 'options': {'temperature': temperature},
    }, timeout);
    final data = _decode(body);
    final message = data['message'];
    final content = message is Map ? message['content'] : null;
    if (content is! String || content.trim().isEmpty) {
      throw const AiBadResponse('Empty answer from the model');
    }
    return content;
  }

  Map<String, Object?> _decode(String body) {
    try {
      final v = jsonDecode(body);
      if (v is Map<String, Object?>) return v;
    } catch (_) {}
    throw const AiBadResponse('The server returned something that is not JSON');
  }

  Future<String> _request(
    String method,
    String path,
    Map<String, Object?>? payload,
    Duration timeout,
  ) async {
    final base = _config().baseUri;
    if (base == null) {
      throw const AiUnavailable('The AI server address is not set');
    }
    final uri = base.replace(path: '${base.path}$path');
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      return await _send(client, method, uri, payload).timeout(timeout);
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

  Future<String> _send(
    HttpClient client,
    String method,
    Uri uri,
    Map<String, Object?>? payload,
  ) async {
    final req = await client.openUrl(method, uri);
    if (payload != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(payload));
    }
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      var detail = '';
      try {
        final d = jsonDecode(text);
        if (d is Map && d['error'] is String) detail = d['error'] as String;
      } catch (_) {}
      throw AiServerError(
        detail.isEmpty ? 'HTTP ${res.statusCode}' : detail,
        statusCode: res.statusCode,
      );
    }
    return text;
  }
}
