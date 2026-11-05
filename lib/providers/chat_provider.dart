import 'package:flutter/foundation.dart';

import 'package:cosmetix/models/social_models.dart';
import 'package:cosmetix/repositories/chat_repository.dart';
import 'package:cosmetix/services/ai/ai_client.dart';
import 'package:cosmetix/services/assistant_service.dart';

/// Why the AI could not answer (decides which message the chat shows).
enum AiFailure {
  unavailable,
  notConfigured,
  timeout,
  rateLimited,

  /// The remote AI is not offered to this user (under 18 or age unknown).
  ageRestricted,
}

class ChatProvider extends ChangeNotifier {
  ChatProvider(this._repo, this._assistant, {bool Function()? shareProfile})
    : _shareProfile = shareProfile ?? (() => false);

  final ChatRepository _repo;
  final AssistantService _assistant;

  /// Whether the user agreed to send the Beauty profile / blacklist to the AI.
  final bool Function() _shareProfile;

  List<ChatMessage> messages = [];
  bool typing = false;

  /// Set when the last answer could not be produced (AI offline, timeout...).
  /// The conversation is kept; [retry] asks again.
  bool aiUnavailable = false;
  String? aiError;

  /// Why the last answer failed (null while everything works).
  AiFailure? aiFailure;

  /// Seconds the AI asked us to wait (rate limit / budget), if known.
  int? retryAfter;
  int? _userId;
  int? _lastProductId;
  String? _lastQuestion;

  Future<void> load(int userId) async {
    _userId = userId;
    try {
      messages = await _repo.messages(userId);
    } catch (e) {
      debugPrint('chat load failed: $e');
    }
    notifyListeners();
  }

  void reset() {
    messages = [];
    _userId = null;
    notifyListeners();
  }

  /// [productId]: the product the question is about (asked from its page).
  Future<void> send(String text, {int? productId}) async {
    final userId = _userId;
    final clean = text.trim();
    if (userId == null || clean.isEmpty || typing) return;
    await _repo.add(userId, clean, isUser: true);
    messages = await _repo.messages(userId);
    _lastQuestion = clean;
    _lastProductId = productId;
    await _answer(userId, clean, productId);
  }

  /// Asks again after a failure (the user message is already saved).
  Future<void> retry() async {
    final userId = _userId;
    final q = _lastQuestion;
    if (userId == null || q == null || typing) return;
    await _answer(userId, q, _lastProductId);
  }

  Future<void> _answer(int userId, String question, int? productId) async {
    typing = true;
    aiUnavailable = false;
    aiError = null;
    aiFailure = null;
    retryAfter = null;
    notifyListeners();
    try {
      // history = everything before the question being answered
      final history = messages.isNotEmpty && messages.last.isUser
          ? messages.sublist(0, messages.length - 1)
          : messages;
      final answer = await _assistant.reply(
        userId: userId,
        text: question,
        history: history,
        productId: productId,
        shareProfile: _shareProfile(),
      );
      await _repo.add(userId, answer, isUser: false);
      messages = await _repo.messages(userId);
      _lastQuestion = null;
    } on AiException catch (e) {
      aiUnavailable = true;
      aiError = e.message;
      aiFailure = switch (e) {
        AiNotAllowed() => AiFailure.ageRestricted,
        AiRateLimited() => AiFailure.rateLimited,
        AiTimeout() => AiFailure.timeout,
        AiUnavailable(message: 'The AI server address is not set') =>
          AiFailure.notConfigured,
        _ => AiFailure.unavailable,
      };
      if (e is AiRateLimited) retryAfter = e.retryAfter;
    } catch (e) {
      debugPrint('chat failed: $e');
      aiUnavailable = true;
      aiError = 'Unexpected error';
      aiFailure = AiFailure.unavailable;
    }
    typing = false;
    notifyListeners();
  }

  Future<void> clear() async {
    final userId = _userId;
    if (userId == null) return;
    await _repo.reset(userId);
    messages = await _repo.messages(userId);
    aiUnavailable = false;
    aiFailure = null;
    _lastQuestion = null;
    notifyListeners();
  }
}
