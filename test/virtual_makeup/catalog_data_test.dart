import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/database/catalog_data.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/database/try_on_data.dart';
import 'package:cosmetix/features/virtual_makeup/virtual_makeup.dart';
import 'package:cosmetix/providers/catalog_provider.dart';
import 'package:cosmetix/repositories/try_on_repository.dart';
import 'package:cosmetix/models/product.dart';

/// A minimal valid catalog product with the given extra fields.
Map<String, Object?> _product([Map<String, Object?> extra = const {}]) => {
  'brand': 'Brand',
  'name': 'Tint 01 Rose',
  'category': 'Макияж',
  'zone': 'Губы',
  'price': 1000,
  'art': 'tube',
  'color': 0xFFAA0000,
  'natural_percent': 50,
  'source_url': 'https://example.test/p',
  'ingredients': <int>[],
  ...extra,
};

Map<String, Object?> _tryOn([Map<String, Object?> extra = const {}]) => {
  'kind': 'lips',
  'colour': 0xFFAA3344,
  'colour_source': 'https://example.test/swatch',
  'colour_status': 'swatch_sampled',
  ...extra,
};

ProductSeed _parse(Map<String, Object?> tryOn) =>
    ProductSeed.fromJson(_product({'try_on': tryOn}));

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('the catalog parser refuses what would be a guess', () {
    test('a complete record is read', () {
      final t = _parse(
        _tryOn({'finish': 'matte', 'finish_source': 'https://x.test'}),
      ).tryOn!;
      expect(t.kind, 'lips');
      expect(t.canTryOn, isTrue);
      expect(t.colour, 0xFFAA3344);
      expect(t.colourStatus, TryOnStatus.swatchSampled);
      expect(t.finish, 'matte');
      expect(_product()['try_on'], isNull);
      expect(ProductSeed.fromJson(_product()).tryOn, isNull);
    });

    test('a colour without a source is refused', () {
      expect(
        () => _parse(_tryOn({'colour_source': null})),
        throwsFormatException,
      );
      expect(
        () => _parse(_tryOn({'colour_source': '  '})),
        throwsFormatException,
      );
    });

    test('a colour whose status is "missing" or unknown is refused', () {
      expect(
        () => _parse(_tryOn({'colour_status': 'missing'})),
        throwsFormatException,
      );
      expect(
        () => _parse(_tryOn({'colour_status': 'sure'})),
        throwsFormatException,
      );
      expect(
        () => _parse(_tryOn({'colour_status': null})),
        throwsFormatException,
      );
    });

    test('a status or a source without a colour is refused', () {
      expect(
        () => _parse(_tryOn({'colour': null})),
        throwsFormatException,
        reason: 'status "swatch_sampled" with no colour',
      );
      expect(
        () => _parse({'kind': 'lips', 'colour_source': 'https://x.test'}),
        throwsFormatException,
      );
    });

    test('a record without a colour is a product that cannot be tried on', () {
      final t = _parse({'kind': 'eyeshadow', 'note': 'no data'}).tryOn!;
      expect(t.canTryOn, isFalse);
      expect(t.colour, isNull);
      expect(t.colourStatus, TryOnStatus.missing);
    });

    test(
      'a transparent colour, an unknown kind, an unsourced finish are refused',
      () {
        expect(
          () => _parse(_tryOn({'colour': 0x00AA3344})),
          throwsFormatException,
        );
        expect(
          () => _parse(_tryOn({'kind': 'mascara'})),
          throwsFormatException,
        );
        expect(
          () => _parse(_tryOn({'finish': 'matte'})),
          throwsFormatException,
        );
        expect(
          () => _parse(_tryOn({'finish': 'sparkly', 'finish_source': 'x'})),
          throwsFormatException,
        );
        expect(() => _parse(_tryOn({'colour': 'red'})), throwsFormatException);
      },
    );

    test('an estimate is called an estimate', () {
      final t = _parse(
        _tryOn({'colour_status': TryOnStatus.legacyEstimate}),
      ).tryOn!;
      expect(t.isApproximate, isTrue);
      final m = _parse(
        _tryOn({'colour_status': TryOnStatus.manufacturer}),
      ).tryOn!;
      expect(m.isApproximate, isFalse);
    });
  });

  group('the real catalog', () {
    late CatalogData catalog;
    setUpAll(() async => catalog = await CatalogData.load());

    Iterable<ProductSeed> withTryOn() =>
        catalog.products.where((p) => p.tryOn != null);

    test('15 makeup products are described, nothing else is touched', () {
      expect(withTryOn().length, 15);
      expect(
        catalog.products.length,
        38,
        reason: 'no product added or removed',
      );
      final kinds = <String, int>{};
      for (final p in withTryOn()) {
        kinds[p.tryOn!.kind] = (kinds[p.tryOn!.kind] ?? 0) + 1;
      }
      expect(kinds, {'lips': 6, 'blush': 2, 'eyeshadow': 7});
    });

    test(
      'no colour is made up: every colour is the old catalog `shade` with its status',
      () {
        for (final p in withTryOn()) {
          final t = p.tryOn!;
          if (t.colour == null) {
            expect(t.colourStatus, TryOnStatus.missing, reason: p.key);
            continue;
          }
          expect(t.colourSource, isNotNull, reason: p.key);
          expect(t.colourStatus, isNot(TryOnStatus.missing), reason: p.key);
          // the only colour data the catalog has today
          expect(t.colourStatus, TryOnStatus.legacyEstimate, reason: p.key);
          expect(t.colour, p.shade, reason: '${p.key}: not the catalog shade');
        }
      },
    );

    test(
      'eyeshadow palettes have no colour yet (one colour cannot describe a palette)',
      () {
        for (final p in withTryOn().where(
          (p) => p.tryOn!.kind == 'eyeshadow',
        )) {
          expect(p.tryOn!.canTryOn, isFalse, reason: p.key);
          expect(p.tryOn!.note, isNotNull, reason: p.key);
        }
      },
    );

    test('shade code and name come from the catalog name, nothing else', () {
      for (final p in withTryOn()) {
        final t = p.tryOn!;
        if (t.shadeCode != null) {
          expect(p.name, contains(t.shadeCode!), reason: p.key);
        }
        if (t.shadeName != null) {
          expect(p.name, endsWith(t.shadeName!), reason: p.key);
        }
      }
    });

    test('the line key is the one the product page uses', () {
      for (final p in withTryOn()) {
        final model = Product(
          id: 1,
          brand: p.brand,
          name: p.name,
          category: p.category,
          zone: p.zone,
          price: p.price,
          inStock: true,
          art: p.art,
          color: p.color,
          description: '',
          naturalPercent: 50,
          createdAt: 0,
        );
        expect(p.tryOn!.line, CatalogProvider.lineOf(model), reason: p.key);
      }
    });

    test('the colours of different shades are different colours', () {
      final lips = [
        for (final p in withTryOn())
          if (p.tryOn!.kind == 'lips') p.tryOn!.colour!,
      ];
      expect(lips.toSet().length, lips.length);
    });

    test('mascara, cushion and skincare have no try-on record', () {
      for (final p in catalog.products) {
        final isMakeupToTry = p.tryOn != null;
        if (p.name.contains('Mascara') || p.name.contains('Cushion')) {
          expect(isMakeupToTry, isFalse, reason: p.key);
        }
        if (p.category != 'Макияж') {
          expect(isMakeupToTry, isFalse, reason: p.key);
        }
      }
    });
  });

  group('the local database', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('cosmetix_tryon'));
    tearDown(() => tmp.deleteSync(recursive: true));

    Future<int> idOf(String brand, String name) async {
      final c = await CatalogData.load();
      return c.products.indexWhere((p) => p.brand == brand && p.name == name) +
          1;
    }

    test(
      'schema version 15 holds the try-on table and rows for 15 products',
      () async {
        final h = DatabaseHelper(path: '${tmp.path}/a.db');
        addTearDown(h.close);
        final db = await h.database;
        expect(DatabaseHelper.dbVersion, 15);
        expect((await db.query('product_shades')).length, 15);
        final r = (await db.rawQuery(
          'SELECT p.name, s.* FROM product_shades s JOIN products p ON p.id = s.product_id '
          "WHERE p.name = 'Ink Mood Glowy Tint 30 Happy Berry'",
        )).single;
        expect(r['kind'], 'lips');
        expect(r['shade_code'], '30');
        expect(r['shade_name'], 'Happy Berry');
        expect(r['colour_status'], 'legacy_estimate');
        expect(r['colour_source'], isNotNull);
      },
    );

    test(
      'a v14 database is upgraded: the new table is filled, nothing is lost',
      () async {
        final path = '${tmp.path}/old.db';
        final h = DatabaseHelper(path: path);
        var db = await h.database;
        final id = await idOf('Peripera', 'Ink Mood Glowy Tint 30 Happy Berry');
        // user data that must survive: a favourite and a cart line
        await db.insert('favorites', {
          'user_id': 1,
          'product_id': id,
          'created_at': 1,
        });
        await db.insert('cart_items', {
          'user_id': 1,
          'product_id': id,
          'store_id': 1,
          'quantity': 2,
          'created_at': 1,
        });
        final before = {
          for (final t in [
            'products',
            'product_prices',
            'favorites',
            'cart_items',
            'users',
            'orders',
          ])
            t: (await db.query(t)).length,
        };
        final shadeColumnBefore = (await db.query(
          'products',
          columns: ['shade'],
          where: 'id = ?',
          whereArgs: [id],
        )).single['shade'];
        // turn it into what the v14 release left: no table, version 14
        await db.execute('DROP TABLE product_shades');
        await db.execute('PRAGMA user_version = 14');
        await h.close();

        final h2 = DatabaseHelper(path: path);
        addTearDown(h2.close);
        db = await h2.database;
        expect(
          (await db.rawQuery('PRAGMA user_version')).single['user_version'],
          15,
        );
        expect((await db.query('product_shades')).length, 15);
        for (final t in before.keys) {
          expect((await db.query(t)).length, before[t], reason: t);
        }
        expect(
          await db.query(
            'favorites',
            where: 'user_id = 1 AND product_id = ?',
            whereArgs: [id],
          ),
          hasLength(1),
        );
        expect(
          (await db.query(
            'cart_items',
            where: 'user_id = 1 AND product_id = ?',
            whereArgs: [id],
          )).single['quantity'],
          2,
        );
        expect(
          (await db.query(
            'products',
            columns: ['shade'],
            where: 'id = ?',
            whereArgs: [id],
          )).single['shade'],
          shadeColumnBefore,
          reason: 'the old products.shade is not touched',
        );
      },
    );

    test('the migration is repeatable and does not duplicate rows', () async {
      final h = DatabaseHelper(path: '${tmp.path}/b.db');
      addTearDown(h.close);
      final db = await h.database;
      await db.execute('PRAGMA user_version = 14');
      await h.close();
      final h2 = DatabaseHelper(path: '${tmp.path}/b.db');
      addTearDown(h2.close);
      final db2 = await h2.database;
      expect((await db2.query('product_shades')).length, 15);
    });

    test('deleting a product removes its try-on row, not other rows', () async {
      final h = DatabaseHelper(path: '${tmp.path}/c.db');
      addTearDown(h.close);
      final db = await h.database;
      final id = await idOf('Peripera', 'Ink The Velvet 31 Wine Nude');
      await db.delete('products', where: 'id = ?', whereArgs: [id]);
      expect((await db.query('product_shades')).length, 14);
    });
  });

  group('what the try-on reads from the catalog (offline, SQLite only)', () {
    late DatabaseHelper h;
    late TryOnRepository repo;
    late CatalogData catalog;

    setUp(() async {
      h = DatabaseHelper(path: inMemoryDatabasePath);
      await h.database;
      repo = TryOnRepository(h);
      catalog = await CatalogData.load();
    });
    tearDown(() => h.close());

    int idOf(String name) =>
        catalog.products.indexWhere((p) => p.name == name) + 1;

    test('the requested product and shade is what comes back', () async {
      final berry = (await repo.item(
        idOf('Ink Mood Glowy Tint 30 Happy Berry'),
      ))!;
      expect(berry.productId, idOf('Ink Mood Glowy Tint 30 Happy Berry'));
      expect(berry.brand, 'Peripera');
      expect(berry.kind, MakeupZone.lips);
      expect(berry.shadeCode, '30');
      expect(berry.shadeName, 'Happy Berry');
      expect(berry.shadeLabel, '30 Happy Berry');
      expect(berry.photo, 'assets/products/8.jpg');
      expect(berry.isApproximate, isTrue);
      expect(berry.colour, const Color(0xFFF48C93));
    });

    test('two shades of one line keep their own colours', () async {
      final berry = (await repo.item(
        idOf('Ink Mood Glowy Tint 30 Happy Berry'),
      ))!;
      final rose = (await repo.item(
        idOf('Ink Mood Glowy Tint 03 Rose In Mind'),
      ))!;
      expect(berry.colour, isNot(rose.colour));
      expect(rose.colour, const Color(0xFFD06F69));
      expect(berry.productId, isNot(rose.productId));
      final line = await repo.sameLine(berry);
      expect(line.map((i) => i.shadeCode), ['03', '30']);
      expect(line.map((i) => i.productId), contains(berry.productId));
      expect(line.firstWhere((i) => i.shadeCode == '03').colour, rose.colour);
    });

    test('a product alone in its line has no shade list', () async {
      final velvet = (await repo.item(idOf('Ink The Velvet 31 Wine Nude')))!;
      expect(await repo.sameLine(velvet), isEmpty);
      final gloss = (await repo.item(idOf('Glasting Color Gloss')))!;
      expect(gloss.lineKey, isNull);
      expect(await repo.sameLine(gloss), isEmpty);
    });

    test(
      'other products of the kind are listed, the item itself is not',
      () async {
        final berry = (await repo.item(
          idOf('Ink Mood Glowy Tint 30 Happy Berry'),
        ))!;
        final others = await repo.otherProducts(berry);
        expect(others.every((i) => i.kind == MakeupZone.lips), isTrue);
        expect(
          others.map((i) => i.productId),
          isNot(contains(berry.productId)),
        );
        expect(
          others.map((i) => i.shadeCode),
          isNot(contains('03')),
          reason: 'shades of its own line are in sameLine',
        );
        expect((await repo.all(MakeupZone.lips)).length, 6);
        expect((await repo.all(MakeupZone.blush)).length, 2);
      },
    );

    test(
      'a product without colour data exists but cannot be tried on',
      () async {
        final palette = (await repo.item(
          idOf('Better Than Palette 05 Shade & Shadow Garden'),
        ))!;
        expect(palette.kind, MakeupZone.eyeshadow);
        expect(palette.canTryOn, isFalse);
        expect(palette.colour, isNull);
        expect(await repo.all(MakeupZone.eyeshadow), isEmpty);
      },
    );

    test('products without a record give nothing', () async {
      expect(await repo.item(idOf('Super Slim Waterproof Mascara')), isNull);
      expect(await repo.item(idOf('Magic Cushion Moist Up')), isNull);
      expect(await repo.item(999), isNull);
    });
  });
}
