import 'package:sqflite/sqflite.dart';

import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/models/care_models.dart';

/// The cosmetic bag, the morning / evening plan and the history of use.
class CareRepository {
  CareRepository(this._helper);

  final DatabaseHelper _helper;

  // ---- cosmetic bag ----

  Future<List<MyProduct>> bag(int userId) async {
    final db = await _helper.database;
    final rows = await db.query(
      'my_products',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(MyProduct.fromMap).toList();
  }

  Future<MyProduct?> bagItem(int id) async {
    final db = await _helper.database;
    final rows = await db.query(
      'my_products',
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : MyProduct.fromMap(rows.first);
  }

  Map<String, Object?> _values(MyProduct p) => {
    'product_id': p.productId,
    'name': p.name.trim(),
    'brand': p.brand.trim(),
    'category': p.category,
    'purchased_at': p.purchasedAt?.millisecondsSinceEpoch,
    'opened_at': p.openedAt?.millisecondsSinceEpoch,
    'pao_months': p.paoMonths,
    'expires_at': p.expiresAt?.millisecondsSinceEpoch,
    'notes': p.notes.trim(),
  };

  Future<int> addToBag(int userId, MyProduct p) async {
    final db = await _helper.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.insert('my_products', {
      'user_id': userId,
      ..._values(p),
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> updateBagItem(MyProduct p) async {
    final db = await _helper.database;
    await db.update(
      'my_products',
      {..._values(p), 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [p.id],
    );
  }

  /// Removes the product from the bag and from the care plan; earlier "used"
  /// entries stay in the history (they keep the product name).
  Future<void> removeFromBag(int id) async {
    final db = await _helper.database;
    await db.delete('my_products', where: 'id = ?', whereArgs: [id]);
  }

  // ---- care plan ----

  Future<List<CareStep>> steps(int userId, CarePeriod period) async {
    final db = await _helper.database;
    final rows = await db.rawQuery(
      '''
SELECT s.id AS step_id, s.position, m.*
FROM care_steps s JOIN my_products m ON m.id = s.my_product_id
WHERE s.user_id = ? AND s.period = ?
ORDER BY s.position, s.id''',
      [userId, period.code],
    );
    return [
      for (final r in rows)
        CareStep(
          id: r['step_id'] as int,
          period: period,
          position: r['position'] as int,
          product: MyProduct.fromMap(r),
        ),
    ];
  }

  /// Adds the product to the end of the plan. False when it is already there.
  Future<bool> addStep(int userId, CarePeriod period, int myProductId) async {
    final db = await _helper.database;
    final last =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT MAX(position) FROM care_steps '
            'WHERE user_id = ? AND period = ?',
            [userId, period.code],
          ),
        ) ??
        -1;
    final id = await db.insert('care_steps', {
      'user_id': userId,
      'period': period.code,
      'position': last + 1,
      'my_product_id': myProductId,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    return id > 0;
  }

  Future<void> removeStep(int stepId) async {
    final db = await _helper.database;
    await db.delete('care_steps', where: 'id = ?', whereArgs: [stepId]);
  }

  /// Rewrites the positions so the steps follow [orderedStepIds].
  Future<void> reorder(List<int> orderedStepIds) async {
    final db = await _helper.database;
    await db.transaction((txn) async {
      for (var i = 0; i < orderedStepIds.length; i++) {
        await txn.update(
          'care_steps',
          {'position': i},
          where: 'id = ?',
          whereArgs: [orderedStepIds[i]],
        );
      }
    });
  }

  // ---- history of use ----

  /// Marks the product as used (or takes the mark back) for one day/period.
  Future<void> setUsed({
    required int userId,
    required DateTime day,
    required CarePeriod period,
    required MyProduct product,
    required bool used,
  }) async {
    final db = await _helper.database;
    if (used) {
      await db.insert('care_logs', {
        'user_id': userId,
        'day': dayKey(day),
        'period': period.code,
        'my_product_id': product.id,
        'product_name': product.title,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      await db.delete(
        'care_logs',
        where: 'user_id = ? AND day = ? AND period = ? AND my_product_id = ?',
        whereArgs: [userId, dayKey(day), period.code, product.id],
      );
    }
  }

  Future<List<CareLogEntry>> logsOfDay(int userId, DateTime day) async {
    final db = await _helper.database;
    final rows = await db.query(
      'care_logs',
      where: 'user_id = ? AND day = ?',
      whereArgs: [userId, dayKey(day)],
    );
    return rows.map(CareLogEntry.fromMap).toList();
  }

  /// Entries of the last [days] days, newest day first.
  Future<List<CareLogEntry>> history(
    int userId, {
    int days = 30,
    DateTime? now,
  }) async {
    final db = await _helper.database;
    final from = dateOnly(
      (now ?? DateTime.now()),
    ).subtract(Duration(days: days - 1));
    final rows = await db.query(
      'care_logs',
      where: 'user_id = ? AND day >= ?',
      whereArgs: [userId, dayKey(from)],
      orderBy: 'day DESC, period, id',
    );
    return rows.map(CareLogEntry.fromMap).toList();
  }
}
