import 'package:sqflite/sqflite.dart';

import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/models/product.dart';

class ProductRepository {
  ProductRepository(this._helper);

  final DatabaseHelper _helper;

  static const _selectWithFav = '''
SELECT p.*, EXISTS(
  SELECT 1 FROM favorites f WHERE f.product_id = p.id AND f.user_id = ?
) AS is_fav FROM products p''';

  Future<List<Product>> getAll(int userId) async {
    final db = await _helper.database;
    final rows = await db.rawQuery(
      '$_selectWithFav ORDER BY p.created_at DESC, p.id',
      [userId],
    );
    return rows.map(Product.fromMap).toList();
  }

  Future<Product?> getById(int id, int userId) async {
    final db = await _helper.database;
    final rows = await db.rawQuery('$_selectWithFav WHERE p.id = ?', [
      userId,
      id,
    ]);
    return rows.isEmpty ? null : Product.fromMap(rows.first);
  }

  Future<List<StorePrice>> getStorePrices(int productId) async {
    final db = await _helper.database;
    final rows = await db.rawQuery(
      '''
SELECT pp.store_id, pp.price, pp.in_stock, s.name, s.distance_m, s.address, s.rating
FROM product_prices pp JOIN stores s ON s.id = pp.store_id
WHERE pp.product_id = ? ORDER BY pp.price''',
      [productId],
    );
    return rows.map(StorePrice.fromMap).toList();
  }

  // ---- favourites ----

  Future<bool> toggleFavorite(int userId, int productId) async {
    final db = await _helper.database;
    final removed = await db.delete(
      'favorites',
      where: 'user_id = ? AND product_id = ?',
      whereArgs: [userId, productId],
    );
    if (removed > 0) return false;
    await db.insert('favorites', {
      'user_id': userId,
      'product_id': productId,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    return true;
  }

  // ---- search history ----

  Future<List<String>> getHistory(int userId, {int limit = 8}) async {
    final db = await _helper.database;
    final rows = await db.query(
      'search_history',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map((r) => r['query'] as String).toList();
  }

  Future<void> addHistory(int userId, String query) async {
    final text = query.trim();
    if (text.isEmpty) return;
    final db = await _helper.database;
    await db.insert('search_history', {
      'user_id': userId,
      'query': text,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeHistory(int userId, String query) async {
    final db = await _helper.database;
    await db.delete(
      'search_history',
      where: 'user_id = ? AND query = ?',
      whereArgs: [userId, query],
    );
  }

  Future<void> clearHistory(int userId) async {
    final db = await _helper.database;
    await db.delete(
      'search_history',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }
}
