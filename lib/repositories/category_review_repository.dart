import 'package:sqflite/sqflite.dart';

import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/services/catalog/category_normalizer.dart';

/// One store category waiting for a person (shown in the admin panel).
class CategoryReviewItem {
  const CategoryReviewItem({
    required this.id,
    required this.store,
    required this.rawCategory,
    required this.normalizedKey,
    required this.productName,
    required this.reason,
    required this.candidates,
    required this.aiHint,
    required this.status,
    this.resolvedType,
    required this.createdAt,
  });

  final int id;
  final String store;
  final String rawCategory;
  final String normalizedKey;
  final String productName;

  /// `ambiguous` or `unknown`.
  final String reason;

  /// Type keys that fit (when ambiguous).
  final List<String> candidates;

  /// Only a hint for the reviewer (from the AI classifier), never applied.
  final String aiHint;

  /// `pending` or `resolved`.
  final String status;
  final String? resolvedType;
  final int createdAt;

  factory CategoryReviewItem.fromMap(Map<String, Object?> m) =>
      CategoryReviewItem(
        id: m['id'] as int,
        store: m['store'] as String,
        rawCategory: m['raw_category'] as String,
        normalizedKey: m['normalized_key'] as String,
        productName: m['product_name'] as String? ?? '',
        reason: m['reason'] as String,
        candidates: [
          for (final c in (m['candidates'] as String? ?? '').split(','))
            if (c.isNotEmpty) c,
        ],
        aiHint: m['ai_hint'] as String? ?? '',
        status: m['status'] as String,
        resolvedType: m['resolved_type'] as String?,
        createdAt: m['created_at'] as int,
      );

  /// What the admin panel / server import reads.
  Map<String, Object?> toJson() => {
    'id': id,
    'store': store,
    'raw_category': rawCategory,
    'normalized_key': normalizedKey,
    'product_name': productName,
    'reason': reason,
    'candidates': candidates,
    'ai_hint': aiHint,
    'status': status,
    'resolved_type': resolvedType,
    'created_at': createdAt,
  };
}

/// The manual review queue of store categories the normalizer is not sure
/// about. The same wording of the same store is queued once.
class CategoryReviewRepository {
  CategoryReviewRepository(this._helper);

  final DatabaseHelper _helper;

  /// Queues [c] (must need review). Returns the queue row id; a wording that
  /// is already queued keeps its row and only fills a missing AI hint.
  Future<int> enqueue(
    NormalizedCategory c, {
    String store = '',
    String productName = '',
    String aiHint = '',
  }) async {
    if (!c.needsReview) {
      throw ArgumentError('${c.raw}: already decided, nothing to review');
    }
    final db = await _helper.database;
    final rows = await db.query(
      'category_review_queue',
      where: 'store = ? AND normalized_key = ?',
      whereArgs: [store, c.key],
    );
    if (rows.isNotEmpty) {
      final id = rows.first['id']! as int;
      if (aiHint.isNotEmpty && (rows.first['ai_hint'] as String).isEmpty) {
        await db.update(
          'category_review_queue',
          {'ai_hint': aiHint},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      return id;
    }
    return db.insert('category_review_queue', {
      'store': store,
      'raw_category': c.raw,
      'normalized_key': c.key,
      'product_name': productName,
      'reason': c.decision.name,
      'candidates': c.candidates.join(','),
      'ai_hint': aiHint,
      'status': 'pending',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<CategoryReviewItem>> pending() async {
    final db = await _helper.database;
    final rows = await db.query(
      'category_review_queue',
      where: "status = 'pending'",
      orderBy: 'created_at, id',
    );
    return rows.map(CategoryReviewItem.fromMap).toList();
  }

  /// A person decided: [typeKey] is the unified category of the wording. The
  /// decision is remembered, see [aliases].
  Future<void> resolve(int id, String typeKey) async {
    final db = await _helper.database;
    await db.update(
      'category_review_queue',
      {
        'status': 'resolved',
        'resolved_type': typeKey,
        'resolved_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// `normalized key -> type key` of everything people resolved. Give it to
  /// `CategoryNormalizer.load(aliases: ...)` so the wording is not asked twice.
  Future<Map<String, String>> aliases() async {
    final db = await _helper.database;
    final rows = await db.query(
      'category_review_queue',
      columns: ['normalized_key', 'resolved_type'],
      where: "status = 'resolved' AND resolved_type IS NOT NULL",
      orderBy: 'resolved_at, id',
    );
    return {
      for (final r in rows)
        r['normalized_key']! as String: r['resolved_type']! as String,
    };
  }

  Future<int> pendingCount() async {
    final db = await _helper.database;
    return Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM category_review_queue WHERE status = 'pending'",
          ),
        ) ??
        0;
  }
}
