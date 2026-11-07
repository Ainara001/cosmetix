import 'package:sqflite/sqflite.dart';

import 'package:cosmetix/database/catalog_structure_data.dart';

/// Checks the links of the catalog structure (DB v16) that SQLite itself cannot
/// check with a constraint. Returns one readable line per problem; an empty
/// list means the structure is consistent. Used by the tests and available to
/// a debug screen; it only reads.
abstract final class CatalogIntegrity {
  static Future<List<String>> check(DatabaseExecutor db) async {
    final problems = <String>[];

    // broken foreign keys of every table
    for (final r in await db.rawQuery('PRAGMA foreign_key_check')) {
      problems.add(
        'foreign key: ${r['table']} row ${r['rowid']} -> ${r['parent']}',
      );
    }

    // a line of a shade must be a known line
    for (final r in await db.rawQuery('''
SELECT s.product_id AS id, s.line_key AS line
FROM product_shades s
LEFT JOIN product_lines l ON l.line_key = s.line_key
WHERE s.line_key IS NOT NULL AND l.line_key IS NULL
''')) {
      problems.add(
        'product ${r['id']} points to the unknown line ${r['line']}',
      );
    }

    // the cells of a product: they exist only when a source gave their number,
    // there are exactly that many, numbered 1..N without a gap, with ids made
    // from their line, variant and position
    final facts = {
      for (final r in await db.query('product_variant_facts'))
        r['product_id']! as int: r['pan_count'] as int?,
    };
    final pans = await db.rawQuery('''
SELECT p.pan_key AS pan_key, p.product_id AS product_id, p.position AS position,
       s.shade_code AS code, l.slug AS slug
FROM product_shade_pans p
LEFT JOIN product_shades s ON s.product_id = p.product_id
LEFT JOIN product_lines l ON l.line_key = s.line_key
ORDER BY p.product_id, p.position
''');
    final byProduct = <int, List<Map<String, Object?>>>{};
    for (final r in pans) {
      byProduct.putIfAbsent(r['product_id']! as int, () => []).add(r);
    }
    for (final e in byProduct.entries) {
      final declared = facts[e.key];
      if (declared == null) {
        problems.add(
          'product ${e.key} has cells but no confirmed number of cells',
        );
        continue;
      }
      if (e.value.length != declared) {
        problems.add(
          'product ${e.key}: ${e.value.length} cells, the source says $declared',
        );
      }
      for (var i = 0; i < e.value.length; i++) {
        final r = e.value[i];
        if (r['position'] != i + 1) {
          problems.add('product ${e.key}: the cells are not numbered 1..N');
          break;
        }
        final slug = r['slug'] as String?;
        final code = r['code'] as String?;
        if (slug == null || code == null) {
          problems.add('product ${e.key}: a cell without a line or a variant');
          break;
        }
        if (r['pan_key'] != panKeyOf(slug, code, i + 1)) {
          problems.add(
            'product ${e.key}: cell id ${r['pan_key']} does not match '
            '${panKeyOf(slug, code, i + 1)}',
          );
        }
      }
    }
    for (final e in facts.entries) {
      final n = e.value;
      if (n != null && !byProduct.containsKey(e.key)) {
        problems.add('product ${e.key}: the source says $n cells, none exist');
      }
    }
    return problems;
  }
}
