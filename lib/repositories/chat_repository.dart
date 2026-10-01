import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/database/seed_data.dart';
import 'package:cosmetix/models/social_models.dart';

class ChatRepository {
  ChatRepository(this._helper);

  final DatabaseHelper _helper;

  Future<List<ChatMessage>> messages(int userId) async {
    final db = await _helper.database;
    final rows = await db.query(
      'chat_messages',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at, id',
    );
    return rows.map(ChatMessage.fromMap).toList();
  }

  Future<void> add(int userId, String text, {required bool isUser}) async {
    final db = await _helper.database;
    await db.insert('chat_messages', {
      'user_id': userId,
      'is_user': isUser ? 1 : 0,
      'text': text,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Removes the conversation and leaves only the greeting.
  Future<void> reset(int userId) async {
    final db = await _helper.database;
    await db.delete('chat_messages', where: 'user_id = ?', whereArgs: [userId]);
    await add(userId, SeedData.greeting, isUser: false);
  }
}
