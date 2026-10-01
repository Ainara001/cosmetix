import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/models/safety_models.dart';

/// Ingredients, personal blacklist and the reactions diary.
class SafetyRepository {
  SafetyRepository(this._helper);

  final DatabaseHelper _helper;

  // ---- ingredients ----

  Future<List<Ingredient>> ingredientsOf(int productId) async {
    final db = await _helper.database;
    final rows = await db.rawQuery(
      '''
SELECT i.* FROM ingredients i
JOIN product_ingredients pi ON pi.ingredient_id = i.id
WHERE pi.product_id = ? ORDER BY i.id''',
      [productId],
    );
    return rows.map(Ingredient.fromMap).toList();
  }

  // ---- blacklist ----

  Future<List<BlacklistItem>> blacklist(int userId) async {
    final db = await _helper.database;
    final rows = await db.query(
      'blacklist',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'is_custom, id',
    );
    return rows.map(BlacklistItem.fromMap).toList();
  }

  Future<void> setBlacklistEnabled(int id, bool enabled) async {
    final db = await _helper.database;
    await db.update(
      'blacklist',
      {'enabled': enabled ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> addCustom(int userId, String name) async {
    final db = await _helper.database;
    await db.insert('blacklist', {
      'user_id': userId,
      'name': name.trim(),
      'description': 'Добавлено вами',
      'enabled': 1,
      'is_custom': 1,
    });
  }

  Future<void> deleteBlacklistItem(int id) async {
    final db = await _helper.database;
    await db.delete('blacklist', where: 'id = ?', whereArgs: [id]);
  }

  // ---- reactions diary ----

  Future<List<Reaction>> reactions(int userId) async {
    final db = await _helper.database;
    final rows = await db.rawQuery(
      '''
SELECT r.*, p.name AS product_name, p.art, p.color
FROM reactions r LEFT JOIN products p ON p.id = r.product_id
WHERE r.user_id = ? ORDER BY r.reaction_date DESC, r.id DESC''',
      [userId],
    );
    return rows.map(Reaction.fromMap).toList();
  }

  Future<Reaction?> reactionById(int id) async {
    final db = await _helper.database;
    final rows = await db.rawQuery(
      '''
SELECT r.*, p.name AS product_name, p.art, p.color
FROM reactions r LEFT JOIN products p ON p.id = r.product_id
WHERE r.id = ?''',
      [id],
    );
    return rows.isEmpty ? null : Reaction.fromMap(rows.first);
  }

  Future<int> addReaction({
    required int userId,
    required int productId,
    required String title,
    required int severity,
    required DateTime date,
    String notes = '',
  }) async {
    final db = await _helper.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.insert('reactions', {
      'user_id': userId,
      'product_id': productId,
      'title': title.trim(),
      'severity': severity,
      'reaction_date': date.millisecondsSinceEpoch,
      'notes': notes.trim(),
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> updateReaction({
    required int id,
    required int productId,
    required String title,
    required int severity,
    required DateTime date,
    String notes = '',
  }) async {
    final db = await _helper.database;
    await db.update(
      'reactions',
      {
        'product_id': productId,
        'title': title.trim(),
        'severity': severity,
        'reaction_date': date.millisecondsSinceEpoch,
        'notes': notes.trim(),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteReaction(int id) async {
    final db = await _helper.database;
    await db.delete('reactions', where: 'id = ?', whereArgs: [id]);
  }
}
