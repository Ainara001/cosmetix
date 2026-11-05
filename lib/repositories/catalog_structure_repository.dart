import 'dart:ui' show Color;

import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/models/palette_models.dart';

/// Reads the structure of cosmetic products (lines, variants, palette cells)
/// from the local SQLite database (DB v16). Offline, read only: products, the
/// cart and the favourites are not changed here.
class CatalogStructureRepository {
  const CatalogStructureRepository(this._helper);

  final DatabaseHelper _helper;

  static ProductLine _line(Map<String, Object?> r) => ProductLine(
    key: r['line_key']! as String,
    slug: r['slug']! as String,
    brand: r['brand']! as String,
    name: r['name']! as String,
    kind: r['kind']! as String,
    sourceUrl: r['source_url']! as String,
    checkedAt: r['checked_at'] as String?,
    confidence: r['confidence']! as String,
  );

  static PalettePan _pan(Map<String, Object?> r) {
    final colour = r['colour'] as int?;
    return PalettePan(
      key: r['pan_key']! as String,
      productId: r['product_id']! as int,
      position: r['position']! as int,
      name: r['name'] as String?,
      finish: r['finish'] as String?,
      colour: colour == null ? null : Color(colour),
      colourStatus: r['colour_status']! as String,
      colourSource: r['colour_source'] as String?,
    );
  }

  /// One summary per product that has a try-on / structure record (id -> summary),
  /// in a single query, for the product lists.
  Future<Map<int, VariantSummary>> summaries() async {
    final db = await _helper.database;
    final rows = await db.rawQuery('''
SELECT s.product_id, s.kind AS product_kind, s.line_key, s.shade_code,
       s.shade_name, l.name AS line_name, l.kind AS line_kind, f.pan_count
FROM product_shades s
LEFT JOIN product_lines l ON l.line_key = s.line_key
LEFT JOIN product_variant_facts f ON f.product_id = s.product_id''');
    return {
      for (final r in rows)
        r['product_id']! as int: VariantSummary(
          productId: r['product_id']! as int,
          lineKey: r['line_key'] as String?,
          lineName: r['line_name'] as String?,
          // a palette is one whose line says so; the product kind of a palette
          // is `eyeshadow`, which a single eyeshadow shares
          kind: (r['line_kind'] as String?) ?? r['product_kind']! as String,
          code: r['shade_code'] as String?,
          name: r['shade_name'] as String?,
          panCount: r['pan_count'] as int?,
        ),
    };
  }

  /// The line with this key (null: there is none).
  Future<ProductLine?> line(String key) async {
    final db = await _helper.database;
    final rows = await db.query(
      'product_lines',
      where: 'line_key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : _line(rows.first);
  }

  /// What is known about one product: its line, variant, facts and cells (null
  /// when the catalog has no try-on or structure record for it).
  Future<VariantInfo?> variant(int productId) async {
    final db = await _helper.database;
    final rows = await db.rawQuery(
      '''
SELECT s.shade_code, s.shade_name, s.line_key,
       f.pan_count, f.source_url AS facts_source, f.checked_at AS facts_checked,
       f.confidence AS facts_confidence
FROM product_shades s
LEFT JOIN product_variant_facts f ON f.product_id = s.product_id
WHERE s.product_id = ?''',
      [productId],
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    final lineKey = r['line_key'] as String?;
    final pans = await db.query(
      'product_shade_pans',
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'position',
    );
    return VariantInfo(
      productId: productId,
      line: lineKey == null ? null : await line(lineKey),
      shadeCode: r['shade_code'] as String?,
      shadeName: r['shade_name'] as String?,
      panCount: r['pan_count'] as int?,
      factsSource: r['facts_source'] as String?,
      factsCheckedAt: r['facts_checked'] as String?,
      factsConfidence: r['facts_confidence'] as String?,
      pans: pans.map(_pan).toList(),
    );
  }

  /// The variants of a line (palette 00, 01, 02 ...), by variant code.
  Future<List<LineVariant>> variantsOfLine(String lineKey) async {
    final db = await _helper.database;
    final rows = await db.rawQuery(
      '''
SELECT p.id, p.price, p.in_stock, s.shade_code, s.shade_name, f.pan_count
FROM product_shades s
JOIN products p ON p.id = s.product_id
LEFT JOIN product_variant_facts f ON f.product_id = s.product_id
WHERE s.line_key = ?
ORDER BY s.shade_code, p.id''',
      [lineKey],
    );
    return [
      for (final r in rows)
        LineVariant(
          productId: r['id']! as int,
          code: r['shade_code'] as String?,
          name: r['shade_name'] as String?,
          price: (r['price'] as int?) ?? 0,
          inStock: (r['in_stock'] as int?) != 0,
          panCount: r['pan_count'] as int?,
        ),
    ];
  }
}
