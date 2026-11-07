import 'dart:ui' show Color;

import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/features/virtual_makeup/virtual_makeup.dart';

/// The try-on catalog (the module's [TryOnCatalog]) read from the local SQLite database (`product_shades`
/// joined with `products`). Offline: no network is used. It only READS; the
/// catalog, cart and favourites are not changed.
class TryOnRepository implements TryOnCatalog {
  const TryOnRepository(this._helper);

  final DatabaseHelper _helper;

  static const _select = '''
SELECT p.id AS product_id, p.brand, p.name, p.art,
       COALESCE((SELECT MIN(o.price) FROM store_offers o
         WHERE o.product_id = p.id AND o.verification = 'verified'
           AND o.price IS NOT NULL), 0) AS price,
       NOT EXISTS (SELECT 1 FROM store_offers o WHERE o.product_id = p.id
         AND o.verification = 'verified' AND o.availability = 'out_of_stock') AS in_stock,
       s.kind, s.line_key, s.shade_code, s.shade_name, s.colour,
       s.colour_source, s.colour_status, s.finish
FROM product_shades s JOIN products p ON p.id = s.product_id''';

  @override
  Future<TryOnItem?> item(int productId) async {
    final db = await _helper.database;
    final rows = await db.rawQuery('$_select WHERE p.id = ?', [productId]);
    if (rows.isEmpty) return null;
    final base = _fromRow(rows.first);
    if (base.canTryOn) return base;
    // a palette has no colour of its own: its first cell with a known colour
    final cells = await _cells(base);
    return cells.isEmpty ? base : cells.first;
  }

  /// The cells of a palette whose colour is known, as items of their own.
  Future<List<TryOnItem>> _cells(TryOnItem palette) async {
    final db = await _helper.database;
    final rows = await db.query(
      'product_shade_pans',
      where: 'product_id = ? AND colour IS NOT NULL',
      whereArgs: [palette.productId],
      orderBy: 'position',
    );
    return [
      for (final r in rows)
        TryOnItem(
          productId: palette.productId,
          brand: palette.brand,
          name: palette.name,
          kind: palette.kind,
          lineKey: palette.lineKey,
          shadeCode: palette.shadeCode,
          shadeName: palette.shadeName,
          colour: Color(r['colour']! as int),
          colourSource: r['colour_source'] as String?,
          status: r['colour_status']! as String,
          finish: (r['finish'] as String?) ?? palette.finish,
          photo: palette.photo,
          price: palette.price,
          inStock: palette.inStock,
          panKey: r['pan_key']! as String,
          panPosition: r['position']! as int,
        ),
    ];
  }

  @override
  Future<List<TryOnItem>> sameLine(TryOnItem item) async {
    if (item.panKey != null) {
      // the cells of this palette (a single measured cell is not a choice)
      final cells = await _cells(item);
      return cells.length < 2 ? const [] : cells;
    }
    final line = item.lineKey;
    if (line == null) return const [];
    final db = await _helper.database;
    final rows = await db.rawQuery(
      '$_select WHERE s.line_key = ? AND s.kind = ? AND s.colour IS NOT NULL '
      'ORDER BY s.shade_code, p.id',
      [line, item.kind.name],
    );
    final all = rows.map(_fromRow).toList();
    return all.length < 2 ? const [] : all;
  }

  @override
  Future<List<TryOnItem>> otherProducts(TryOnItem item) async {
    final db = await _helper.database;
    final rows = await db.rawQuery(
      '$_select WHERE s.kind = ? AND s.colour IS NOT NULL '
      'AND (s.line_key IS NULL OR s.line_key IS NOT ?) AND p.id <> ? '
      'ORDER BY p.brand, p.name',
      [item.kind.name, item.lineKey, item.productId],
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<List<TryOnItem>> all(MakeupZone kind) async {
    final db = await _helper.database;
    final rows = await db.rawQuery(
      '$_select WHERE s.kind = ? AND s.colour IS NOT NULL '
      'ORDER BY p.brand, p.name',
      [kind.name],
    );
    return rows.map(_fromRow).toList();
  }

  static TryOnItem _fromRow(Map<String, Object?> r) {
    // `art` holds "tube" or "tube|assets/products/7.jpg"
    final art = (r['art'] as String?) ?? '';
    final bar = art.indexOf('|');
    final colour = r['colour'] as int?;
    return TryOnItem(
      productId: r['product_id']! as int,
      brand: r['brand']! as String,
      name: r['name']! as String,
      kind: MakeupZone.values.byName(r['kind']! as String),
      lineKey: r['line_key'] as String?,
      shadeCode: r['shade_code'] as String?,
      shadeName: r['shade_name'] as String?,
      colour: colour == null ? null : Color(colour),
      colourSource: r['colour_source'] as String?,
      status: (r['colour_status'] as String?) ?? 'missing',
      finish: r['finish'] as String?,
      photo: bar < 0 ? null : art.substring(bar + 1),
      price: (r['price'] as int?) ?? 0,
      inStock: (r['in_stock'] as int?) != 0,
    );
  }
}
