import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

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
    String? photoPath,
  }) async {
    final db = await _helper.database;
    await db.insert('reviews', {
      'product_id': productId,
      'user_id': userId,
      'author': author,
      'rating': rating,
      'body': body.trim(),
      'photo_path': photoPath,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> update(
    int id,
    int rating,
    String body, {
    String? photoPath,
  }) async {
    final db = await _helper.database;
    await db.update(
      'reviews',
      {'rating': rating, 'body': body.trim(), 'photo_path': photoPath},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(int id) async {
    final db = await _helper.database;
    await db.delete('reviews', where: 'id = ?', whereArgs: [id]);
  }

  /// The picker returns a temporary file; keep a copy next to the database so
  /// the photo survives app restarts.
  Future<String> savePhoto(String sourcePath) async {
    final dir = Directory(p.join(await getDatabasesPath(), 'review_photos'));
    await dir.create(recursive: true);
    final dest = p.join(
      dir.path,
      '${DateTime.now().microsecondsSinceEpoch}${p.extension(sourcePath)}',
    );
    await File(sourcePath).copy(dest);
    return dest;
  }
}
