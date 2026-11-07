import 'package:sqflite/sqflite.dart';

import 'package:cosmetix/core/beauty/beauty_codes.dart';
import 'package:cosmetix/models/ai_models.dart';
import 'package:cosmetix/models/recommendation.dart';
import 'package:cosmetix/models/safety_models.dart';

import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/repositories/offer_sql.dart';

class ProductRepository {
  ProductRepository(this._helper);

  final DatabaseHelper _helper;

  static const _selectWithFav = '''
SELECT p.*, EXISTS(
  SELECT 1 FROM favorites f WHERE f.product_id = p.id AND f.user_id = ?
) AS is_fav, $verifiedOfferColumns FROM products p''';

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

  /// The VERIFIED offers of a product with a price (the demo rows of
  /// `product_prices` are not read). Each carries when it was checked, where
  /// the information comes from and the link when there is one.
  Future<List<StorePrice>> getStorePrices(int productId) async {
    final db = await _helper.database;
    final rows = await db.rawQuery(
      '''
SELECT o.store_id, o.price, o.availability, o.checked_at AS updated_at,
  o.source AS offer_source, o.method, o.url, o.url_kind, o.old_price,
  s.name, s.distance_m, s.address, s.rating, s.lat, s.lng,
  s.chain, s.hours, s.source AS loc_source
FROM store_offers o JOIN stores s ON s.id = o.store_id
WHERE o.product_id = ? AND o.verification = 'verified' AND o.price IS NOT NULL
ORDER BY o.price''',
      [productId],
    );
    return rows.map(StorePrice.fromMap).toList();
  }

  /// Every shop that has a position (for the map).
  Future<List<StoreInfo>> getStores() async {
    final db = await _helper.database;
    final rows = await db.query(
      'stores',
      where: 'lat IS NOT NULL AND lng IS NOT NULL',
      orderBy: 'id',
    );
    return rows.map(StoreInfo.fromMap).toList();
  }

  /// Products with their suitability traits and ingredients, for the
  /// recommendation logic (curated and AI-classified traits are merged).
  Future<List<ProductCandidate>> candidates(int userId) async {
    final db = await _helper.database;
    final products = (await db.rawQuery(
      '$_selectWithFav ORDER BY p.created_at DESC, p.id',
      [userId],
    )).map(Product.fromMap).toList();

    Future<Map<int, Set<String>>> grouped(String table, String column) async {
      final rows = await db.rawQuery(
        'SELECT DISTINCT product_id, $column AS v FROM $table',
      );
      final out = <int, Set<String>>{};
      for (final r in rows) {
        out
            .putIfAbsent(r['product_id']! as int, () => {})
            .add(r['v']! as String);
      }
      return out;
    }

    final skin = await grouped('product_skin_types', 'skin_type');
    final colors = await grouped('product_color_types', 'color_type');
    final under = await grouped('product_undertones', 'undertone');
    final concerns = await grouped('product_concerns', 'concern');
    final tags = await grouped('product_tags', 'tag');

    final ingRows = await db.rawQuery('''
SELECT pi.product_id, i.* FROM product_ingredients pi
JOIN ingredients i ON i.id = pi.ingredient_id ORDER BY i.id''');
    final ingredients = <int, List<Ingredient>>{};
    for (final r in ingRows) {
      ingredients
          .putIfAbsent(r['product_id']! as int, () => [])
          .add(Ingredient.fromMap(r));
    }

    Set<T> codes<T>(Set<String>? raw, T? Function(String) parse) => {
      for (final c in raw ?? const <String>{})
        if (parse(c) != null) parse(c) as T,
    };

    return [
      for (final p in products)
        ProductCandidate(
          product: p,
          skinTypes: codes(skin[p.id], SkinType.fromCode),
          colorTypes: codes(colors[p.id], ColorType.fromCode),
          undertones: codes(under[p.id], Undertone.fromCode),
          concerns: codes(concerns[p.id], SkinConcern.fromCode),
          tags: tags[p.id] ?? const {},
          ingredients: ingredients[p.id] ?? const [],
        ),
    ];
  }

  // ---- AI classification cache ----

  /// Products the AI has not classified yet.
  Future<List<Product>> unclassified(int userId) async {
    final db = await _helper.database;
    final rows = await db.rawQuery(
      '$_selectWithFav WHERE p.id NOT IN '
      '(SELECT product_id FROM product_ai_classification) ORDER BY p.id',
      [userId],
    );
    return rows.map(Product.fromMap).toList();
  }

  Future<int> classifiedCount() async {
    final db = await _helper.database;
    return Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM product_ai_classification'),
        ) ??
        0;
  }

  /// Caches the classification and writes its traits with source 'ai'
  /// (curated 'seed' traits are never touched). Low confidence answers are
  /// cached (so we do not ask again) but add no traits.
  Future<void> saveAiClassification(
    int productId,
    String model,
    ProductClassification c, {
    double minConfidence = 0.5,
  }) async {
    final db = await _helper.database;
    await db.transaction((txn) async {
      for (final t in const [
        ['product_skin_types'],
        ['product_color_types'],
        ['product_undertones'],
        ['product_concerns'],
      ]) {
        await txn.delete(
          t.first,
          where: "product_id = ? AND source = 'ai'",
          whereArgs: [productId],
        );
      }
      if (c.confidence >= minConfidence) {
        Future<void> put(String table, String col, Iterable<String> v) async {
          for (final x in v) {
            await txn.insert(table, {
              'product_id': productId,
              col: x,
              'source': 'ai',
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }

        await put(
          'product_skin_types',
          'skin_type',
          c.skinTypes.map((e) => e.code),
        );
        await put(
          'product_color_types',
          'color_type',
          c.colorTypes.map((e) => e.code),
        );
        await put(
          'product_undertones',
          'undertone',
          c.undertones.map((e) => e.code),
        );
        await put('product_concerns', 'concern', c.concerns.map((e) => e.code));
      }
      await txn.insert('product_ai_classification', {
        'product_id': productId,
        'model': model,
        'confidence': c.confidence,
        'explanation': c.explanation,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
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
