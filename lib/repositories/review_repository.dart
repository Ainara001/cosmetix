import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/models/social_models.dart';

class ReviewRepository {
  ReviewRepository(this._helper);

  final DatabaseHelper _helper;

  Future<List<Review>> forProduct(int productId) async {
    final db = await _helper.database;
    final rows = await db.query(
      'reviews',
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'created_at DESC',
    );
    return rows.map(Review.fromMap).toList();
  }

  Future<void> add({
    required int productId,
    required int userId,
    required String author,
    required int rating,
    required String body,
  }) async {
    final db = await _helper.database;
    await db.insert('reviews', {
      'product_id': productId,
      'user_id': userId,
      'author': author,
      'rating': rating,
      'body': body.trim(),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> update(int id, int rating, String body) async {
    final db = await _helper.database;
    await db.update(
      'reviews',
      {'rating': rating, 'body': body.trim()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(int id) async {
    final db = await _helper.database;
    await db.delete('reviews', where: 'id = ?', whereArgs: [id]);
  }
}
