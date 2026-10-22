import 'dart:convert';

import 'package:cosmetix/core/utils/app_paths.dart';
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
    String? photoPath,
  }) async {
    final db = await _helper.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.transaction((txn) async {
      final id = await txn.insert('reactions', {
        'user_id': userId,
        'product_id': productId,
        'title': title.trim(),
        'severity': severity,
        'reaction_date': date.millisecondsSinceEpoch,
        'notes': notes.trim(),
        'photo_path': AppPaths.toStored(photoPath),
        'created_at': now,
        'updated_at': now,
      });
      await txn.insert('reaction_history', {
        'reaction_id': id,
        'changed_at': now,
        'summary': jsonEncode({'created': true}),
      });
      return id;
    });
  }

  /// Saves the changes and, when something really changed, adds an entry to
  /// the change history. The old photo file is deleted when it was replaced
  /// or removed.
  Future<void> updateReaction({
    required int id,
    required int productId,
    required String title,
    required int severity,
    required DateTime date,
    String notes = '',
    String? photoPath,
  }) async {
    final db = await _helper.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    String? oldPhoto;
    await db.transaction((txn) async {
      final rows = await txn.rawQuery(
        '''
SELECT r.*, p.brand AS product_brand, p.name AS product_name
FROM reactions r LEFT JOIN products p ON p.id = r.product_id
WHERE r.id = ?''',
        [id],
      );
      if (rows.isEmpty) return;
      final old = rows.first;
      oldPhoto = old['photo_path'] as String?;
      final newStored = AppPaths.toStored(photoPath);
      final changes = <String, List<String>>{};
      void diff(String field, Object? before, Object? after) {
        if ('$before' != '$after') changes[field] = ['$before', '$after'];
      }

      if (old['product_id'] != productId) {
        final n = await txn.query(
          'products',
          columns: ['brand', 'name'],
          where: 'id = ?',
          whereArgs: [productId],
        );
        changes['product'] = [
          '${old['product_brand'] ?? ''} ${old['product_name'] ?? ''}'.trim(),
          n.isEmpty ? '' : '${n.first['brand']} ${n.first['name']}'.trim(),
        ];
      }
      diff('title', old['title'], title.trim());
      diff('severity', old['severity'], severity);
      diff(
        'date',
        _day(DateTime.fromMillisecondsSinceEpoch(old['reaction_date'] as int)),
        _day(date),
      );
      diff('notes', _cut(old['notes'] as String? ?? ''), _cut(notes.trim()));
      if (oldPhoto != newStored) {
        changes['photo'] = [
          oldPhoto == null ? 'none' : 'set',
          newStored == null ? 'none' : 'set',
        ];
      }
      await txn.update(
        'reactions',
        {
          'product_id': productId,
          'title': title.trim(),
          'severity': severity,
          'reaction_date': date.millisecondsSinceEpoch,
          'notes': notes.trim(),
          'photo_path': newStored,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      if (changes.isNotEmpty) {
        await txn.insert('reaction_history', {
          'reaction_id': id,
          'changed_at': now,
          'summary': jsonEncode({'changes': changes}),
        });
      }
      if (oldPhoto == newStored) oldPhoto = null; // nothing to delete
    });
    if (oldPhoto != null) await AppPaths.deleteFile(oldPhoto);
  }

  Future<void> deleteReaction(int id) async {
    final db = await _helper.database;
    final rows = await db.query(
      'reactions',
      columns: ['photo_path'],
      where: 'id = ?',
      whereArgs: [id],
    );
    await db.delete('reactions', where: 'id = ?', whereArgs: [id]);
    if (rows.isNotEmpty) {
      await AppPaths.deleteFile(rows.first['photo_path'] as String?);
    }
  }

  /// The change history of a record, newest first.
  Future<List<ReactionChange>> reactionHistory(int reactionId) async {
    final db = await _helper.database;
    final rows = await db.query(
      'reaction_history',
      where: 'reaction_id = ?',
      whereArgs: [reactionId],
      orderBy: 'changed_at DESC, id DESC',
    );
    final out = <ReactionChange>[];
    for (final r in rows) {
      try {
        final j = jsonDecode(r['summary'] as String) as Map<String, Object?>;
        final raw = j['changes'];
        out.add(
          ReactionChange(
            id: r['id'] as int,
            changedAt: DateTime.fromMillisecondsSinceEpoch(
              r['changed_at'] as int,
            ),
            created: j['created'] == true,
            fields: {
              if (raw is Map)
                for (final e in raw.entries)
                  if (e.value is List && (e.value as List).length == 2)
                    '${e.key}': (
                      '${(e.value as List)[0]}',
                      '${(e.value as List)[1]}',
                    ),
            },
          ),
        );
      } catch (_) {
        // an unreadable entry is skipped, the rest of the history still shows
      }
    }
    return out;
  }

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _cut(String s) =>
      s.length <= 120 ? s : '${s.substring(0, 120)}…';
}
