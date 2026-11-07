import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/database/catalog_data.dart';
import 'package:cosmetix/database/catalog_integrity.dart';
import 'package:cosmetix/database/catalog_structure_data.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/database/seed_data.dart';
import 'package:cosmetix/repositories/catalog_structure_repository.dart';

Map<String, Object?> _line([Map<String, Object?> extra = const {}]) => {
  'key': 'Brand|palette',
  'slug': 'brand-palette',
  'brand': 'Brand',
  'name': 'Palette',
  'kind': 'eyeshadow_palette',
  'source_url': 'https://example.test/p',
  'checked_at': '2026-11-05',
  'confidence': 'third_party',
  ...extra,
};

Map<String, Object?> _variant([Map<String, Object?> extra = const {}]) => {
  'product': 'Brand|Palette 01 Rose',
  'pan_count': 4,
  'source_url': 'https://example.test/p',
  'checked_at': '2026-11-05',
  'confidence': 'official_page',
  ...extra,
};

String _json(List<Map<String, Object?>> lines, List<Map<String, Object?>> v) {
  String enc(Object? o) => o == null
      ? 'null'
      : o is String
      ? '"${o.replaceAll('"', '\\"')}"'
      : '$o';
  String obj(Map<String, Object?> m) =>
      '{${m.entries.map((e) => '"${e.key}": ${enc(e.value)}').join(',')}}';
  return '{"lines":[${lines.map(obj).join(',')}],'
      '"variants":[${v.map(obj).join(',')}]}';
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('the lines file refuses what would be a guess', () {
    test('a complete file is read', () {
      final s = CatalogStructure.parse(_json([_line()], [_variant()]));
      expect(s.lines.single.slug, 'brand-palette');
      expect(s.variants.single.panCount, 4);
      expect(s.variants.single.checkedAt, '2026-11-05');
    });

    for (final c in <String, String Function()>{
      'a number of cells that is "unconfirmed"': () => _json(
        [_line()],
        [
          _variant({'confidence': 'unconfirmed'}),
        ],
      ),
      'a number of cells of 0': () => _json(
        [_line()],
        [
          _variant({'pan_count': 0}),
        ],
      ),
      'a source that is not a link': () => _json(
        [_line()],
        [
          _variant({'source_url': 'somewhere'}),
        ],
      ),
      'a date that is not YYYY-MM-DD': () => _json(
        [_line()],
        [
          _variant({'checked_at': '05.11.2026'}),
        ],
      ),
      'an unknown confidence': () => _json(
        [_line()],
        [
          _variant({'confidence': 'sure'}),
        ],
      ),
      'a slug with capitals': () => _json([
        _line({'slug': 'Brand Palette'}),
      ], []),
      'a line listed twice': () => _json([_line(), _line()], []),
      'a product listed twice': () =>
          _json([_line()], [_variant(), _variant()]),
      'two lines with one slug': () => _json([
        _line(),
        _line({'key': 'Brand|other'}),
      ], []),
    }.entries) {
      test('refuses ${c.key}', () {
        expect(() => CatalogStructure.parse(c.value()), throwsFormatException);
      });
    }

    test('refuses a product that is not in the catalog', () async {
      final catalog = await CatalogData.load();
      final s = CatalogStructure.parse(_json([_line()], [_variant()]));
      expect(() => s.validateAgainst(catalog), throwsFormatException);
    });
  });

  group('the shipped lines.json', () {
    late CatalogData catalog;
    late CatalogStructure structure;
    setUpAll(() async {
      catalog = await CatalogData.load();
      structure = await CatalogStructure.load();
    });

    test('agrees with the product catalog', () {
      structure.validateAgainst(catalog);
    });

    test('every line a try-on record names is listed', () {
      final known = structure.lineByKey;
      final used = {
        for (final p in catalog.products)
          if (p.tryOn?.line != null) p.tryOn!.line!,
      };
      expect(used, isNotEmpty);
      expect(known.keys.toSet().containsAll(used), isTrue);
      // and no line is listed that nothing uses
      expect(used.containsAll(known.keys), isTrue);
    });

    test('six Better Than Palette variants have ten cells, Eyes none', () {
      final byProduct = {for (final v in structure.variants) v.productKey: v};
      final palettes = [
        for (final p in catalog.products)
          if (p.name.startsWith('Better Than Palette')) p,
      ];
      expect(palettes, hasLength(6));
      for (final p in palettes) {
        expect(byProduct[p.key]!.panCount, 10, reason: p.name);
        expect(byProduct[p.key]!.confidence, isNot(FactConfidence.unconfirmed));
      }
      final eyes = byProduct['Rom&nd|Better Than Eyes']!;
      expect(eyes.panCount, isNull);
      expect(eyes.confidence, FactConfidence.unconfirmed);
    });

    test('a cell id is built from its line, variant and place', () {
      expect(
        panKeyOf('romand-better-than-palette', '02', 7),
        'romand-better-than-palette/02/07',
      );
    });
  });

  group('the local database (v16)', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('cosmetix_v16'));
    tearDown(() => tmp.deleteSync(recursive: true));

    Future<int> idOf(String name) async {
      final c = await CatalogData.load();
      return c.products.indexWhere((p) => p.name == name) + 1;
    }

    test(
      'a new install has the structure, consistent and colourless',
      () async {
        final h = DatabaseHelper(path: '${tmp.path}/new.db');
        addTearDown(h.close);
        final db = await h.database;
        expect(DatabaseHelper.dbVersion, 16);
        expect(
          (await db.rawQuery('PRAGMA user_version')).single['user_version'],
          16,
        );
        expect(await db.query('product_lines'), hasLength(4));
        expect(await db.query('product_variant_facts'), hasLength(7));
        final pans = await db.query('product_shade_pans');
        expect(pans, hasLength(60));
        expect(pans.every((r) => r['colour'] == null), isTrue);
        expect(pans.every((r) => r['colour_status'] == 'missing'), isTrue);
        expect(pans.every((r) => r['name'] == null), isTrue);
        expect(await CatalogIntegrity.check(db), isEmpty);
        // ids of the products are still position + 1
        final c = await CatalogData.load();
        for (var i = 0; i < c.products.length; i++) {
          final r = await db.query(
            'products',
            where: 'id = ?',
            whereArgs: [i + 1],
          );
          expect(r.single['name'], c.products[i].name);
        }
      },
    );

    test('a v15 database is upgraded and nothing is lost', () async {
      final path = '${tmp.path}/v15.db';
      final h = DatabaseHelper(path: path);
      var db = await h.database;
      final id = await idOf('Better Than Palette 02 Mahogany Garden');
      final lip = await idOf('Ink Mood Glowy Tint 30 Happy Berry');
      await db.insert('favorites', {
        'user_id': 1,
        'product_id': id,
        'created_at': 1,
      });
      await db.insert('cart_items', {
        'user_id': 1,
        'product_id': id,
        'store_id': 1,
        'quantity': 3,
        'created_at': 1,
      });
      const tables = [
        'products',
        'product_prices',
        'product_shades',
        'favorites',
        'cart_items',
        'users',
        'orders',
        'reviews',
      ];
      final before = {for (final t in tables) t: await db.query(t)};
      // what the v15 release left: no v16 tables, version 15
      await db.execute('DROP TABLE product_shade_pans');
      await db.execute('DROP TABLE product_variant_facts');
      await db.execute('DROP TABLE product_lines');
      await db.execute('PRAGMA user_version = 15');
      await h.close();

      final h2 = DatabaseHelper(path: path);
      addTearDown(h2.close);
      db = await h2.database;
      expect(
        (await db.rawQuery('PRAGMA user_version')).single['user_version'],
        16,
      );
      for (final t in tables) {
        expect(await db.query(t), before[t], reason: '$t is unchanged');
      }
      expect(await db.query('product_shade_pans'), hasLength(60));
      expect(await CatalogIntegrity.check(db), isEmpty);
      // the old colour estimate of a lipstick is still a legacy estimate
      final s = (await db.query(
        'product_shades',
        where: 'product_id = ?',
        whereArgs: [lip],
      )).single;
      expect(s['colour_status'], 'legacy_estimate');
      expect(s['colour'], isNotNull);
      // the favourite and the cart line of the palette still work
      expect(
        await db.query('favorites', where: 'product_id = ?', whereArgs: [id]),
        hasLength(1),
      );
      expect(
        (await db.query(
          'cart_items',
          where: 'product_id = ?',
          whereArgs: [id],
        )).single['quantity'],
        3,
      );
    });

    test('the migration is repeatable and keeps a stored colour', () async {
      final path = '${tmp.path}/again.db';
      final h = DatabaseHelper(path: path);
      var db = await h.database;
      final id = await idOf('Better Than Palette 01 Pampas Garden');
      const key = 'romand-better-than-palette/01/03';
      // a colour that a later measurement stores for one cell
      await db.update(
        'product_shade_pans',
        {
          'colour': 0xFF8A4B3C,
          'colour_status': 'measured_swatch',
          'colour_source': 'test measurement',
          'measurement_ref': 'test-ref-1',
        },
        where: 'pan_key = ?',
        whereArgs: [key],
      );
      await db.execute('PRAGMA user_version = 15');
      await h.close();

      final h2 = DatabaseHelper(path: path);
      addTearDown(h2.close);
      db = await h2.database;
      await SeedData.applyCatalogStructure(db); // and once more by hand
      final pans = await db.query(
        'product_shade_pans',
        where: 'product_id = ?',
        whereArgs: [id],
        orderBy: 'position',
      );
      expect(pans, hasLength(10));
      final kept = pans.firstWhere((r) => r['pan_key'] == key);
      expect(kept['colour'], 0xFF8A4B3C);
      expect(kept['colour_status'], 'measured_swatch');
      expect(kept['measurement_ref'], 'test-ref-1');
      expect(await db.query('product_shade_pans'), hasLength(60));
      expect(await db.query('product_lines'), hasLength(4));
      expect(await CatalogIntegrity.check(db), isEmpty);
    });

    group('the constraints', () {
      late DatabaseHelper h;
      late dynamic db;
      late int id;
      setUp(() async {
        h = DatabaseHelper(path: '${tmp.path}/c.db');
        db = await h.database;
        id = await idOf('Better Than Palette 02 Mahogany Garden');
      });
      tearDown(() => h.close());

      Map<String, Object?> pan(Map<String, Object?> extra) => {
        'pan_key': 'x/${extra.hashCode}',
        'product_id': id,
        'position': 11,
        'colour_status': 'missing',
        ...extra,
      };

      Future<void> rejects(Map<String, Object?> row) async {
        await expectLater(
          db.insert('product_shade_pans', row),
          throwsA(anything),
        );
      }

      test('a colour without a source is refused', () async {
        await rejects(
          pan({'colour': 0xFF112233, 'colour_status': 'swatch_sampled'}),
        );
      });
      test('a colour with the status missing is refused', () async {
        await rejects(
          pan({
            'colour': 0xFF112233,
            'colour_source': 's',
            'colour_status': 'missing',
          }),
        );
      });
      test('a status without a colour is refused', () async {
        await rejects(pan({'colour_status': 'legacy_estimate'}));
      });
      test('a transparent colour is refused', () async {
        await rejects(
          pan({
            'colour': 0x00112233,
            'colour_source': 's',
            'colour_status': 'swatch_sampled',
          }),
        );
      });
      test('a measured colour needs its measurement', () async {
        await rejects(
          pan({
            'colour': 0xFF112233,
            'colour_source': 's',
            'colour_status': 'measured_swatch',
          }),
        );
      });
      test('an unknown status or finish is refused', () async {
        await rejects(pan({'colour_status': 'guess'}));
        await rejects(pan({'finish': 'glitter-ish'}));
      });
      test('two cells cannot share a place of one palette', () async {
        await rejects(pan({'position': 3}));
      });
      test('a cell id cannot be used twice', () async {
        await rejects(pan({'pan_key': 'romand-better-than-palette/02/01'}));
      });
      test('a cell needs an existing product', () async {
        await rejects(pan({'product_id': 99999}));
      });
      test('a position below 1 is refused', () async {
        await rejects(pan({'position': 0}));
      });
      test('a valid cell with a source is accepted', () async {
        await db.insert(
          'product_shade_pans',
          pan({
            'position': 11,
            'colour': 0xFF112233,
            'colour_source': 'test',
            'colour_status': 'swatch_sampled',
          }),
        );
      });

      test('deleting a product removes its cells and nothing else', () async {
        await db.delete('products', where: 'id = ?', whereArgs: [id]);
        expect(await db.query('product_shade_pans'), hasLength(50));
        expect(await db.query('product_variant_facts'), hasLength(6));
        expect(await db.query('product_lines'), hasLength(4));
      });
    });

    group('the integrity check', () {
      late DatabaseHelper h;
      late dynamic db;
      setUp(() async {
        h = DatabaseHelper(path: '${tmp.path}/i.db');
        db = await h.database;
      });
      tearDown(() => h.close());

      test('finds a missing cell', () async {
        await db.delete(
          'product_shade_pans',
          where: 'pan_key = ?',
          whereArgs: ['romand-better-than-palette/02/10'],
        );
        final p = await CatalogIntegrity.check(db);
        expect(p, hasLength(1));
        expect(p.single, contains('9 cells, the source says 10'));
      });

      test('finds a gap in the numbering', () async {
        await db.delete(
          'product_shade_pans',
          where: 'pan_key = ?',
          whereArgs: ['romand-better-than-palette/02/04'],
        );
        await db.insert('product_shade_pans', {
          'pan_key': 'romand-better-than-palette/02/11',
          'product_id': await idOf('Better Than Palette 02 Mahogany Garden'),
          'position': 11,
          'colour_status': 'missing',
        });
        final p = await CatalogIntegrity.check(db);
        expect(p.join('\n'), contains('not numbered 1..N'));
      });

      test(
        'finds cells of a product whose number of cells is not confirmed',
        () async {
          final eyes = await idOf('Better Than Eyes');
          await db.insert('product_shade_pans', {
            'pan_key': 'x/1',
            'product_id': eyes,
            'position': 1,
            'colour_status': 'missing',
          });
          final p = await CatalogIntegrity.check(db);
          expect(p.join('\n'), contains('no confirmed number of cells'));
        },
      );

      test('finds a number of cells without cells', () async {
        await db.delete('product_shade_pans');
        final p = await CatalogIntegrity.check(db);
        expect(p, hasLength(6));
      });

      test('finds a wrong cell id and an unknown line', () async {
        await db.update(
          'product_shade_pans',
          {'pan_key': 'wrong/id'},
          where: 'pan_key = ?',
          whereArgs: ['romand-better-than-palette/03/05'],
        );
        await db.update(
          'product_shades',
          {'line_key': 'No|such line'},
          where: 'product_id = ?',
          whereArgs: [await idOf('Ink The Velvet 31 Wine Nude')],
        );
        final p = (await CatalogIntegrity.check(db)).join('\n');
        expect(p, contains('does not match'));
        expect(p, contains('unknown line No|such line'));
      });
    });

    group('the repository', () {
      late DatabaseHelper h;
      late CatalogStructureRepository repo;
      setUp(() async {
        h = DatabaseHelper(path: '${tmp.path}/r.db');
        await h.database;
        repo = CatalogStructureRepository(h);
      });
      tearDown(() => h.close());

      test('lists the variants of a palette line', () async {
        final v = await repo.variantsOfLine('Rom&nd|better than palette');
        expect(v.map((e) => e.code), ['00', '01', '02', '03', '05', '07']);
        expect(v.every((e) => e.panCount == 10), isTrue);
        // each variant keeps the price of its own catalog row
        expect(
          {for (final e in v) e.code!: e.price},
          {
            '00': 5200,
            '01': 5200,
            '02': 5200,
            '03': 5200,
            '05': 4800,
            '07': 5200,
          },
        );
      });

      test('reads a palette with its ten colourless cells', () async {
        final id = await idOf('Better Than Palette 02 Mahogany Garden');
        final v = (await repo.variant(id))!;
        expect(v.line!.name, 'Better Than Palette');
        expect(v.line!.isPalette, isTrue);
        expect(v.shadeCode, '02');
        expect(v.shadeName, 'Mahogany Garden');
        expect(v.panCount, 10);
        expect(v.factsConfidence, FactConfidence.officialPageUnchecked);
        expect(v.factsCheckedAt, '2026-11-05');
        expect(v.pans.map((p) => p.position), [
          for (var i = 1; i <= 10; i++) i,
        ]);
        expect(v.tryablePans, isEmpty);
        expect(v.pans.first.key, 'romand-better-than-palette/02/01');
        expect(v.pans.every((p) => p.isApproximate && !p.canTryOn), isTrue);
      });

      test('Better Than Eyes has no cells and no invented number', () async {
        final v = (await repo.variant(await idOf('Better Than Eyes')))!;
        expect(v.panCount, isNull);
        expect(v.pans, isEmpty);
        expect(v.factsConfidence, FactConfidence.unconfirmed);
      });

      test('a lipstick is a variant of its line without cells', () async {
        final v = (await repo.variant(
          await idOf('Ink Mood Glowy Tint 30 Happy Berry'),
        ))!;
        expect(v.line!.name, 'Ink Mood Glowy Tint');
        expect(v.pans, isEmpty);
        expect(v.isPalette, isFalse);
        final all = await repo.variantsOfLine(v.line!.key);
        expect(all.map((e) => e.code), ['03', '30']);
      });

      test('a product without try-on data is simply unknown', () async {
        expect(
          await repo.variant(await idOf('Super Slim Waterproof Mascara')),
          isNull,
        );
        expect(await repo.line('nope'), isNull);
      });

      test('a stored colour is read back with its status', () async {
        final id = await idOf('Better Than Palette 02 Mahogany Garden');
        final db = await h.database;
        await db.update(
          'product_shade_pans',
          {
            'colour': 0xFF8A4B3C,
            'colour_status': 'measured_swatch',
            'colour_source': 'test',
            'measurement_ref': 'r1',
          },
          where: 'pan_key = ?',
          whereArgs: ['romand-better-than-palette/02/03'],
        );
        final v = (await repo.variant(id))!;
        final p = v.pans[2];
        expect(p.canTryOn, isTrue);
        expect(p.isApproximate, isFalse);
        expect(v.tryablePans, hasLength(1));
      });
    });
  });
}
