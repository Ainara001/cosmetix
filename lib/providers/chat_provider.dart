import 'package:flutter/foundation.dart';

import 'package:cosmetix/models/social_models.dart';
import 'package:cosmetix/repositories/chat_repository.dart';
import 'package:cosmetix/services/ai/ollama_client.dart';
import 'package:cosmetix/services/assistant_service.dart';

class ChatProvider extends ChangeNotifier {
  ChatProvider(this._repo, this._assistant);

  final ChatRepository _repo;
  final AssistantService _assistant;

  List<ChatMessage> messages = [];
  bool typing = false;

  /// Set when the last answer could not be produced (AI offline, timeout...).
  /// The conversation is kept; [retry] asks again.
  bool aiUnavailable = false;
  String? aiError;
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
      );
      await _repo.add(userId, answer, isUser: false);
      messages = await _repo.messages(userId);
      _lastQuestion = null;
    } on AiException catch (e) {
      aiUnavailable = true;
      aiError = e.message;
    } catch (e) {
      debugPrint('chat failed: $e');
      aiUnavailable = true;
      aiError = 'Unexpected error';
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
    _lastQuestion = null;
    notifyListeners();
  }
}
