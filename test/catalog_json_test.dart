import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/app.dart';
import 'package:cosmetix/database/catalog_data.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/database/seed_data.dart';
import 'package:cosmetix/models/ai_models.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/services/ai/ai_client.dart';
import 'package:cosmetix/services/ai/product_classifier.dart';
import 'package:cosmetix/core/beauty/beauty_codes.dart';
import 'package:cosmetix/repositories/category_review_repository.dart';
import 'package:cosmetix/repositories/product_repository.dart';
import 'package:cosmetix/repositories/user_repository.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/services/catalog/category_import_service.dart';
import 'package:cosmetix/services/catalog/category_normalizer.dart';
import 'widget_test.dart' show pumpUntil;

String _file(String path) => File(path).readAsStringSync();

/// A one-product catalog for the parser tests.
Map<String, Object?> _product({Map<String, Object?> extra = const {}}) => {
  'brand': 'Brand',
  'name': 'Thing',
  'category': 'Макияж',
  'price': 100,
  'art': 'tube',
  'color': 1,
  'natural_percent': 80,
  'source_url': 'https://example.com/thing',
  ...extra,
};

CatalogData _parse(List<Map<String, Object?>> products) => CatalogData.parse(
  jsonEncode({'ingredients': []}),
  jsonEncode({'products': products}),
);

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('the catalog is read from JSON', () {
    late CatalogData catalog;
    setUpAll(() async => catalog = await CatalogData.load());

    test('38 products and their ingredients are in the JSON files', () {
      expect(catalog.products.length, 38);
      expect(catalog.ingredients.length, 19);
      // ids are 1-based positions, as in the old Dart seed
      expect(catalog.ingredients.first.name, 'Вода / Aqua');
      expect(catalog.products.first.key, '3CE|Super Slim Waterproof Mascara');
      expect(catalog.firstNewProduct, 18);
    });

    test('every real product has a source page, a photo file and a shade '
        'only where the colour is known', () {
      for (final p in catalog.products.where((p) => !p.demo)) {
        expect(p.sourceUrl, startsWith('https://'), reason: p.key);
        expect(p.inci, isNotEmpty, reason: p.key);
        expect(File(p.photo!).existsSync(), isTrue, reason: p.key);
      }
      expect(catalog.products.where((p) => p.shade != null).length, 16);
      // the only made-up product says so
      expect(catalog.products.where((p) => p.demo).map((p) => p.brand), [
        'Cosmetix',
      ]);
    });

    test('no country is stated without the page that proves it', () {
      for (final p in catalog.products) {
        expect(p.country == null, p.countrySource == null, reason: p.key);
      }
    });

    test('a fresh database holds exactly what the JSON says', () async {
      final helper = DatabaseHelper(path: inMemoryDatabasePath);
      addTearDown(helper.close);
      final db = await helper.database;
      final rows = await db.query('products', orderBy: 'id');
      expect(rows.length, catalog.products.length);
      for (var i = 0; i < rows.length; i++) {
        final p = catalog.products[i];
        final r = rows[i];
        expect(r['id'], i + 1);
        expect(r['brand'], p.brand);
        expect(r['name'], p.name);
        expect(r['price'], p.price);
        expect(r['old_price'], p.oldPrice);
        expect(r['in_stock'], p.inStock ? 1 : 0);
        expect(r['art'], p.artValue);
        expect(r['inci'], p.inci);
        expect(r['source_url'], p.sourceUrl);
        expect(r['shade'], p.shade);
        expect(r['featured'], p.featured ? 1 : 0);
        expect(r['country'], p.country);
        final links = await db.query(
          'product_ingredients',
          where: 'product_id = ?',
          whereArgs: [i + 1],
        );
        expect(
          links.map((l) => l['ingredient_id']).toSet(),
          p.ingredients.toSet(),
          reason: p.key,
        );
      }
      expect(
        (await db.query('ingredients')).length,
        catalog.ingredients.length,
      );
      final traits = catalog.products.where((p) => p.traits != null);
      expect(traits.length, 37);
      expect(
        (await db.query('product_color_types')).length,
        traits.fold<int>(0, (n, p) => n + p.traits!.colorTypes.length),
      );
    });

    test('the parser refuses what would be a guess', () {
      expect(
        () => _parse([
          _product(extra: {'country': 'Корея'}),
        ]),
        throwsA(isA<FormatException>()),
        reason: 'country without a source',
      );
      expect(
        () => _parse([
          _product(extra: {'country_source': 'https://example.com'}),
        ]),
        throwsA(isA<FormatException>()),
        reason: 'source without a country',
      );
      expect(
        () => _parse([
          _product(extra: {'country': 'Корея', 'country_source': 'not a url'}),
        ]),
        throwsA(isA<FormatException>()),
        reason: 'a source must be a page',
      );
      expect(
        () => _parse([
          _product(extra: {'source_url': ''}),
        ]),
        throwsA(isA<FormatException>()),
        reason: 'a real product needs a source',
      );
      expect(
        () => _parse([_product(), _product()]),
        throwsA(isA<FormatException>()),
        reason: 'twice',
      );
      expect(
        () => _parse([
          _product(
            extra: {
              'ingredients': [3],
            },
          ),
        ]),
        throwsA(isA<FormatException>()),
        reason: 'ingredient 3 does not exist',
      );
      expect(
        _parse([
          _product(
            extra: {
              'country': 'Корея',
              'country_source': 'https://example.com/made-in',
            },
          ),
        ]).products.single.country,
        'Корея',
      );
      expect(
        _parse([
          _product(extra: {'source_url': '', 'demo': true}),
        ]).products.length,
        1,
        reason: 'a made-up product needs no source, it is marked demo',
      );
    });
  });

  group('migration 14: country columns and the review queue', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('cosmetix_c14'));
    tearDown(() => tmp.deleteSync(recursive: true));

    /// A database of an older release: [version] 12 has no `birth_year` yet,
    /// 13 has it; neither has the country columns nor the queue.
    Future<String> makeOld(int version) async {
      final path = '${tmp.path}/v$version.db';
      final h = DatabaseHelper(path: path);
      final db = await h.database;
      // what the release before this one looks like: no country columns,
      // no queue, version 12
      await db.execute('DROP TABLE category_review_queue');
      await db.execute('ALTER TABLE products DROP COLUMN country');
      await db.execute('ALTER TABLE products DROP COLUMN country_source');
      if (version < 13) {
        await db.execute('ALTER TABLE users DROP COLUMN birth_year');
      }
      await db.execute('PRAGMA user_version = $version');
      await db.insert('products', {
        'id': 500,
        'brand': 'My shop',
        'name': 'Мой товар',
        'category': 'Макияж',
        'price': 1,
        'color': 0,
        'created_at': 0,
      });
      await h.close();
      return path;
    }

    for (final from in [12, 13]) {
      test('a v$from database gets the columns and keeps its data', () async {
        final path = await makeOld(from);
        final h = DatabaseHelper(path: path);
        addTearDown(h.close);
        final db = await h.database;
        expect(
          (await db.rawQuery('PRAGMA user_version')).single['user_version'],
          DatabaseHelper.dbVersion,
        );
        final cols = (await db.rawQuery(
          'PRAGMA table_info(products)',
        )).map((c) => c['name']);
        expect(cols, containsAll(['country', 'country_source']));
        expect((await db.query('products')).length, 39);
        expect(
          (await db.query('products', where: 'id = 500')).single['country'],
          isNull,
        );
        expect(await db.query('category_review_queue'), isEmpty);
        // step 13 (birth_year) ran for a v12 database, was not repeated for v13
        expect(
          (await db.rawQuery('PRAGMA table_info(users)')).map((c) => c['name']),
          contains('birth_year'),
        );
      });
    }

    test('applyCountries writes only what the catalog proves', () async {
      final helper = DatabaseHelper(path: inMemoryDatabasePath);
      addTearDown(helper.close);
      final db = await helper.database;
      final catalog = CatalogData.parse(
        _file(CatalogData.ingredientsAsset),
        jsonEncode({
          'products': [
            _product(
              extra: {
                'brand': '3CE',
                'name': 'Super Slim Waterproof Mascara',
                'country': 'Южная Корея',
                'country_source': 'https://example.com/official-page',
              },
            ),
          ],
        }),
      );
      await SeedData.applyCountries(db, catalog);
      final rows = await db.query(
        'products',
        columns: ['name', 'country', 'country_source'],
        where: 'country IS NOT NULL',
      );
      expect(rows.length, 1);
      expect(rows.single['name'], 'Super Slim Waterproof Mascara');
      expect(rows.single['country'], 'Южная Корея');
      expect(
        rows.single['country_source'],
        'https://example.com/official-page',
      );
    });
  });

  group('the product page shows the country', () {
    Future<void> settle(WidgetTester t) async {
      for (var i = 0; i < 8; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> open(WidgetTester t, DatabaseHelper h, int id) async {
      t.view.physicalSize = const Size(1080, 7000);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      addTearDown(() => t.runAsync(h.close));
      await t.runAsync(() => UserRepository(h).setCurrentUser(1));
      await t.pumpWidget(CosmetixApp(helper: h));
      await pumpUntil(t, find.text('Кабинет'));
      await settle(t);
      t
          .state<NavigatorState>(find.byType(Navigator).first)
          .pushNamed(AppRoutes.product, arguments: id);
      await settle(t);
    }

    testWidgets('no source found: it says "not stated", not a guess', (
      t,
    ) async {
      final h = DatabaseHelper(path: inMemoryDatabasePath);
      await open(t, h, 12);
      expect(find.text('Страна производителя: не указана'), findsOneWidget);
    });

    testWidgets('a country with its source is shown with the site', (t) async {
      final h = DatabaseHelper(path: inMemoryDatabasePath);
      await t.runAsync(() async {
        final db = await h.database;
        await db.update('products', {
          'country': 'Канада',
          'country_source': 'https://example.com/the-ordinary/made-in',
        }, where: 'id = 12');
      });
      await open(t, h, 12);
      expect(
        find.text('Страна производителя: Канада (источник: example.com)'),
        findsOneWidget,
      );
      final p = await t.runAsync(() => ProductRepository(h).getById(12, 1));
      expect(p!.country, 'Канада');
    });
  });

  group('category normalizer', () {
    late CategoryNormalizer n;
    setUpAll(() async => n = await CategoryNormalizer.load());

    test('the same words in any order and form give one category', () {
      for (final raw in [
        'увлажняющий крем',
        'крем увлажняющий',
        'Крем увлажняющий для лица',
        'КРЕМЫ УВЛАЖНЯЮЩИЕ',
        'Увлажняющего крема',
        'moisturizing cream',
        'cream, moisturizing',
        'Крем',
      ]) {
        final c = n.normalize(raw);
        expect(c.typeName, 'Крем', reason: raw);
        expect(c.decision, CategoryDecision.matched, reason: raw);
      }
      expect(
        n.normalize('увлажняющий крем').key,
        n.normalize('крем увлажняющий').key,
      );
    });

    test('other types and several wordings of each', () {
      const expected = {
        'Сыворотка': ['Сыворотка для лица', 'сыворотки', 'serum face'],
        'Тонер': ['Тонер для лица', 'тоник увлажняющий', 'Toner'],
        'Тушь': ['тушь для ресниц', 'Mascara', 'тушь объёмная'],
        'Шампунь': ['Шампуни', 'shampoo'],
        'Тинт для губ': ['тинт для губ', 'Lip Tint', 'тинт'],
        'Тональная основа': ['тональный крем', 'крем тональный', 'BB крем'],
        'Солнцезащитное средство': ['солнцезащитный крем', 'Крем SPF 50'],
        'Мицеллярная вода': ['мицеллярная вода', 'Water micellar'],
        'Парфюмерия': ['парфюмерная вода', 'Eau de Parfum', 'духи'],
        'Бальзам для губ': ['бальзам для губ', 'Lip Sleeping Mask'],
        'Тени для век': ['палетка теней', 'Тени для век', 'eyeshadow palette'],
      };
      expected.forEach((name, wordings) {
        for (final w in wordings) {
          expect(n.normalize(w).typeName, name, reason: w);
        }
      });
    });

    test('a longer phrase beats a single word', () {
      // "крем" alone is a cream, but with "тональный" it is a foundation
      expect(n.normalize('тональный крем').typeKey, 'foundation');
      expect(n.normalize('крем').typeKey, 'cream');
    });

    test('doubtful cases are not guessed: they go to review', () {
      final gelCream = n.normalize('крем-гель');
      expect(gelCream.decision, CategoryDecision.ambiguous);
      expect(gelCream.typeKey, isNull);
      expect(gelCream.candidates, ['cream', 'gel']);
      // the same wording the other way round is the same case
      expect(n.normalize('Гель-крем').key, gelCream.key);

      expect(n.normalize('бальзам').decision, CategoryDecision.unknown);
      expect(n.normalize('набор кистей').decision, CategoryDecision.unknown);
      expect(n.normalize('').decision, CategoryDecision.unknown);
      expect(n.normalize('12 мл').decision, CategoryDecision.unknown);
      expect(n.normalize('крем').needsReview, isFalse);
      expect(gelCream.needsReview, isTrue);
    });

    test('a hair dye cream is not a cream', () {
      expect(n.normalize('крем-краска для волос').typeKey, 'hair_dye');
    });

    test('a decision of a person is remembered', () async {
      final learned = await CategoryNormalizer.load(
        aliases: {n.normalize('крем-гель').key: 'cream'},
      );
      final c = learned.normalize('Гель-крем');
      expect(c.decision, CategoryDecision.alias);
      expect(c.typeName, 'Крем');
    });

    test('every phrase and alias points to a known type', () {
      expect(
        () => CategoryNormalizer.fromJson(
          jsonEncode({
            'ignore': [],
            'types': [
              {
                'key': 'a',
                'name': 'A',
                'words': ['aaa'],
              },
            ],
            'phrases': [
              {
                'words': ['x', 'y'],
                'type': 'zzz',
              },
            ],
          }),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('review queue', () {
    late DatabaseHelper helper;
    late CategoryNormalizer n;
    late CategoryReviewRepository queue;
    setUp(() async {
      helper = DatabaseHelper(path: inMemoryDatabasePath);
      queue = CategoryReviewRepository(helper);
      n = await CategoryNormalizer.load();
    });
    tearDown(() => helper.close());

    test('sure cases skip the queue, doubtful ones wait there once', () async {
      final service = CategoryImportService(n, queue);
      final sure = await service.process(
        store: 'Золотое Яблоко',
        rawCategory: 'Крем увлажняющий',
      );
      expect(sure.typeKey, 'cream');
      expect(sure.queueId, isNull);
      expect(await queue.pendingCount(), 0);

      final a = await service.process(
        store: 'Диона',
        rawCategory: 'Крем-гель',
        productName: 'Aqua Gel Cream',
      );
      expect(a.typeKey, isNull);
      expect(a.queueId, isNotNull);
      // the same wording again (other order) is the same row
      final b = await service.process(store: 'Диона', rawCategory: 'гель-крем');
      expect(b.queueId, a.queueId);
      // another shop asks separately
      final c = await service.process(
        store: 'Золотое Яблоко',
        rawCategory: 'гель-крем',
      );
      expect(c.queueId, isNot(a.queueId));

      final pending = await queue.pending();
      expect(pending.length, 2);
      expect(pending.first.reason, 'ambiguous');
      expect(pending.first.candidates, ['cream', 'gel']);
      expect(pending.first.productName, 'Aqua Gel Cream');
      expect(pending.first.toJson()['status'], 'pending');
    });

    test(
      'resolving removes it from the queue and teaches the normalizer',
      () async {
        final service = CategoryImportService(n, queue);
        final r = await service.process(store: 'Диона', rawCategory: 'Бальзам');
        expect(r.category.decision, CategoryDecision.unknown);
        await queue.resolve(r.queueId!, 'lip_balm');
        expect(await queue.pending(), isEmpty);
        final learned = await CategoryNormalizer.load(
          aliases: await queue.aliases(),
        );
        expect(learned.normalize('бальзам').typeName, 'Бальзам для губ');
      },
    );

    test('a decided category cannot be queued', () async {
      expect(
        () => queue.enqueue(n.normalize('крем')),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('the AI classifier is only a hint stored for the reviewer', () async {
      final service = CategoryImportService(
        n,
        queue,
        _FakeClassifier(
          const ProductClassification(
            skinTypes: {SkinType.dry},
            confidence: 0.8,
            explanation: 'увлажняет',
          ),
        ),
      );
      final r = await service.process(
        store: 'Диона',
        rawCategory: 'Крем-гель',
        productName: 'Aqua Gel Cream',
      );
      // the category is still undecided, the hint is text only
      expect(r.typeKey, isNull);
      final item = (await queue.pending()).single;
      expect(item.aiHint, contains('подсказка, не решение'));
      expect(item.aiHint, contains('Сухая'));
      expect(item.resolvedType, isNull);
    });

    test('an offline classifier does not break the import', () async {
      final service = CategoryImportService(n, queue, _FakeClassifier(null));
      final r = await service.process(store: 'Диона', rawCategory: 'Бальзам');
      expect(r.queueId, isNotNull);
      expect((await queue.pending()).single.aiHint, '');
    });

    test('no hint text for an empty answer', () {
      expect(
        CategoryImportService.hintText(
          const ProductClassification(confidence: 0),
        ),
        '',
      );
    });
  });
}

/// Answers like the AI classifier (null: the server is not reachable).
class _FakeClassifier implements ProductClassifier {
  _FakeClassifier(this.answer);

  final ProductClassification? answer;

  @override
  Future<ProductClassification> classify(Product p) async =>
      answer ?? (throw const AiUnavailable('offline'));

  @override
  Future<ClassificationReport> classifyPending(
    int userId, {
    int limit = 40,
    void Function(int done, int total)? onProgress,
  }) => throw UnimplementedError();
}
