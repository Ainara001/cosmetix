import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/foundation.dart';

import 'package:cosmetix/models/social_models.dart';
import 'package:cosmetix/repositories/chat_repository.dart';
import 'package:cosmetix/services/assistant_service.dart';

class ChatProvider extends ChangeNotifier {
  ChatProvider(this._repo, this._assistant);

  final ChatRepository _repo;
  final AssistantService _assistant;

  List<ChatMessage> messages = [];
  bool typing = false;
  int? _userId;

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

  Future<void> send(String text) async {
    final userId = _userId;
    final clean = text.trim();
    if (userId == null || clean.isEmpty || typing) return;
    await _repo.add(userId, clean, isUser: true);
    messages = await _repo.messages(userId);
    typing = true;
    notifyListeners();
    String answer;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      answer = await _assistant.reply(clean, userId);
    } catch (_) {
      answer = tr('Что-то пошло не так, попробуйте переформулировать вопрос.');
    }
    await _repo.add(userId, answer, isUser: false);
    messages = await _repo.messages(userId);
    typing = false;
    notifyListeners();
  }

  Future<void> clear() async {
    final userId = _userId;
    if (userId == null) return;
    await _repo.reset(userId);
    messages = await _repo.messages(userId);
    notifyListeners();
  }
}
