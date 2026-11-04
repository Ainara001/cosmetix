// Exports the app's built-in catalog (what a fresh install of the SQLite
// database contains after all migrations) to server/seed/catalog.json, the
// source of the PostgreSQL seed. Run it from the repository root:
//
//   flutter test tool/export_server_seed.dart
//
// Nothing is invented here: every value is read from lib/database/seed_data.dart
// and lib/database/store_data.dart by running the real seeding code.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/database/database_helper.dart';

void main() {
  // A file in tool/ has no flutter_test_config.dart, so the test binding is not
  // set up for it. Since the catalog is read from assets (rootBundle), seeding
  // fails with "Binding has not yet been initialized" without this line.
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('export catalog to server/seed/catalog.json', () async {
    final helper = DatabaseHelper(path: inMemoryDatabasePath);
    final db = await helper.database;

    Future<List<Map<String, Object?>>> all(String sql) => db.rawQuery(sql);

    final newest = (await all('SELECT MAX(created_at) AS m FROM products'))
        .first['m']! as int;
    final products = [
      for (final r in await all('SELECT * FROM products ORDER BY id'))
        {
          for (final e in r.entries)
            if (e.key != 'created_at') e.key: e.value,
          // created_at depends on the export time: keep only the age relative
          // to the newest product, so the file is the same on every run
          'age_ms': newest - (r['created_at']! as int),
        },
    ];

    final data = {
      'meta': {
        'generatedBy': 'tool/export_server_seed.dart',
        'sqliteSchemaVersion': DatabaseHelper.dbVersion,
        'note':
            'Prices and stock in products.price and product_prices come from '
            'the app demo data (source = "demo"); they are not real shop prices.',
      },
      'stores': await all('SELECT * FROM stores ORDER BY id'),
      'ingredients': await all('SELECT * FROM ingredients ORDER BY id'),
      'products': products,
      'product_ingredients': await all(
        'SELECT * FROM product_ingredients ORDER BY product_id, ingredient_id',
      ),
      'product_prices': await all('SELECT * FROM product_prices ORDER BY id'),
      'product_skin_types': await all(
        'SELECT * FROM product_skin_types ORDER BY product_id, skin_type',
      ),
      'product_color_types': await all(
        'SELECT * FROM product_color_types ORDER BY product_id, color_type',
      ),
      'product_undertones': await all(
        'SELECT * FROM product_undertones ORDER BY product_id, undertone',
      ),
      'product_concerns': await all(
        'SELECT * FROM product_concerns ORDER BY product_id, concern',
      ),
      'product_tags': await all(
        'SELECT * FROM product_tags ORDER BY product_id, tag',
      ),
    };
    File(
      'server/seed/catalog.json',
    ).writeAsStringSync('${const JsonEncoder.withIndent(' ').convert(data)}\n');
    await helper.close();
  });
}
