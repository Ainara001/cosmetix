import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/app.dart';
import 'package:cosmetix/core/beauty/beauty_codes.dart';
import 'package:cosmetix/core/beauty/color_palettes.dart';
import 'package:cosmetix/core/theme/app_theme.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/database/seed_data.dart';
import 'package:cosmetix/database/store_data.dart';
import 'package:cosmetix/models/ai_models.dart';
import 'package:cosmetix/models/beauty_profile.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/models/store_offer.dart';
import 'package:cosmetix/providers/cart_provider.dart';
import 'package:cosmetix/providers/location_provider.dart';
import 'package:cosmetix/repositories/cart_repository.dart';
import 'package:cosmetix/providers/nav_provider.dart';
import 'package:cosmetix/repositories/product_repository.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/routes/route_args.dart';
import 'package:cosmetix/screens/beauty/color_test_screen.dart';
import 'package:cosmetix/screens/stores/stores_map_screen.dart';
import 'package:cosmetix/services/ai/beauty_profile_merger.dart';
import 'package:cosmetix/services/assistant_service.dart';
import 'package:cosmetix/services/beauty_test_flow.dart';
import 'package:cosmetix/services/color_test_service.dart';
import 'package:cosmetix/widgets/common_widgets.dart';
import 'widget_test.dart' show pumpUntil;

StorePrice _offer({bool inStock = true, int? qty, String hours = ''}) =>
    StorePrice(
      storeId: 1,
      storeName: 'S',
      distanceM: 100,
      address: 'A',
      rating: 0,
      price: 1000,
      inStock: inStock,
      availability: inStock ? Availability.inStock : Availability.outOfStock,
      qty: qty,
      hours: hours,
    );

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('shops: real points, demo offers', () {
    late DatabaseHelper helper;
    late ProductRepository repo;

    setUp(() {
      helper = DatabaseHelper(path: inMemoryDatabasePath);
      repo = ProductRepository(helper);
    });
    tearDown(() => helper.close());

    test('a fresh install has every real shop with a position', () async {
      final stores = await repo.getStores();
      expect(stores.length, StoreData.stores.length);
      expect(stores.length, 13);
      final chains = stores.map((s) => s.chain).toSet();
      expect(
        chains,
        containsAll(['Диона', 'Подружка', 'MonAmie', 'Золотое Яблоко']),
      );
      // all in Astana: inside a 25 km box around the centre
      for (final s in stores) {
        expect(
          StoreData.meters(
            StoreData.centerLat,
            StoreData.centerLng,
            s.lat,
            s.lng,
          ),
          lessThan(25000),
          reason: s.address,
        );
        expect(s.address, isNotEmpty);
      }
      // the unverified addresses say so
      final podruzhka = stores.where((s) => s.chain == 'Подружка');
      expect(podruzhka.length, 3);
      expect(podruzhka.every((s) => s.source.contains('не проверен')), isTrue);
    });

    test(
      'offers come only from verified shop offers, never from the demo rows',
      () async {
        final prices = await repo.getStorePrices(12);
        expect(prices.length, 13); // the test fixture verifies every demo row
        expect(prices.every((p) => !p.demo), isTrue);
        expect(prices.every((p) => p.hasPosition), isTrue);
        expect(prices.any((p) => p.level == StockLevel.out), isTrue);
        expect(prices.any((p) => p.level == StockLevel.inStock), isTrue);
        expect(prices.every((p) => p.updatedAt != null), isTrue);
      },
    );

    test('without verified offers there is no price at all', () async {
      final saved = DatabaseHelper.afterSeed;
      DatabaseHelper.afterSeed = null;
      addTearDown(() => DatabaseHelper.afterSeed = saved);
      final bare = DatabaseHelper(path: inMemoryDatabasePath);
      addTearDown(bare.close);
      final r = ProductRepository(bare);
      expect(await r.getStorePrices(12), isEmpty);
      final p = (await r.getById(12, 1))!;
      expect(p.price, 0, reason: 'the seed price is a demo value, not shown');
      expect(p.hasPrice, isFalse);
      expect(p.availability, Availability.unknown);
      expect(p.inStock, isTrue, reason: 'unknown is not out of stock');
    });

    test('the demo data is stable: the same on every install', () async {
      final a = await repo.getStorePrices(5);
      final other = DatabaseHelper(path: inMemoryDatabasePath);
      addTearDown(other.close);
      final b = await ProductRepository(other).getStorePrices(5);
      expect(
        a.map((p) => '${p.storeId}:${p.price}:${p.qty}').toList(),
        b.map((p) => '${p.storeId}:${p.price}:${p.qty}').toList(),
      );
    });

    test('migration v9: old shops become real, prices and ids stay', () async {
      final db = await helper.database;
      // what an install of the previous release looks like
      await db.delete('stores', where: 'id > 3');
      await db.update('stores', {
        'name': 'Korean Beauty',
        'address': 'ул. Абая 45',
        'lat': null,
        'lng': null,
        'chain': '',
        'hours': '',
        'source': 'demo',
      }, where: 'id = 1');
      await db.update('product_prices', {'qty': null}, where: 'store_id <= 3');
      await db.update('product_prices', {
        'price': 7777,
        'in_stock': 0,
      }, where: 'product_id = 3 AND store_id = 2');
      final old = await db.query('product_prices', where: 'store_id <= 3');
      expect(old.length, 38 * 3);

      await SeedData.applyRealStores(db);

      final stores = await repo.getStores();
      expect(stores.length, 13);
      final s1 = stores.firstWhere((s) => s.id == 1);
      expect(s1.name, 'Диона');
      expect(s1.address, 'пр. Сарыарка, 15');
      // ids of the old shops are kept; a cart row for store 2 is still valid
      expect(stores.map((s) => s.id), containsAll([1, 2, 3, 4, 13]));
      // the old price and "out of stock" survive, the units are added
      final kept = (await db.query(
        'product_prices',
        where: 'product_id = 3 AND store_id = 2',
      )).single;
      expect(kept['price'], 7777);
      expect(kept['in_stock'], 0);
      expect(kept['qty'], 0);
      // every product got an offer in every new shop
      expect(
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM product_prices'),
        ),
        38 * 13,
      );
      // running it again changes nothing
      await SeedData.applyRealStores(db);
      expect((await repo.getStores()).length, 13);
      expect(
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM product_prices'),
        ),
        38 * 13,
      );
    });

    test('distance: Baiterek to the first shop is a few kilometres', () {
      final m = StoreData.meters(
        StoreData.centerLat,
        StoreData.centerLng,
        StoreData.stores.first.lat,
        StoreData.stores.first.lng,
      );
      expect(m, closeTo(4700, 400));
      expect(StoreData.meters(51.1, 71.4, 51.1, 71.4), 0);
    });
  });

  group('stock level and opening hours', () {
    test('stock level', () {
      expect(_offer(inStock: false, qty: 0).level, StockLevel.out);
      expect(_offer(qty: 2).level, StockLevel.low);
      expect(_offer(qty: 3).level, StockLevel.low);
      expect(_offer(qty: 4).level, StockLevel.inStock);
      expect(_offer().level, StockLevel.inStock); // units unknown
    });

    test('openStatus follows the hours', () {
      final at = DateTime(2026, 11, 1, 15);
      expect(
        _offer(hours: 'Ежедневно 10:00–22:00').openStatus(at),
        'открыто до 22:00',
      );
      expect(
        _offer(
          hours: 'Ежедневно 10:00–22:00',
        ).openStatus(DateTime(2026, 11, 1, 23)),
        'закрыто, откроется в 10:00',
      );
      expect(_offer(hours: '').openStatus(at), isEmpty);
    });

    test('withDistance keeps everything else', () {
      final o = _offer(qty: 2).withDistance(1234);
      expect(o.distanceM, 1234);
      expect(o.qty, 2);
      expect(o.price, 1000);
    });
  });

  group('location', () {
    test('without a position distances come from the centre', () async {
      final loc = LocationProvider(fetcher: () async => null);
      expect(loc.isReal, isFalse);
      expect(loc.origin.lat, StoreData.centerLat);
      await loc.refresh();
      expect(loc.isReal, isFalse);
      expect(loc.unavailable, isTrue);
      final s = StoreData.stores.first;
      expect(
        loc.distanceTo(s.lat, s.lng),
        StoreData.meters(
          StoreData.centerLat,
          StoreData.centerLng,
          s.lat,
          s.lng,
        ),
      );
    });

    test('with a position distances come from the user', () async {
      final s = StoreData.stores.first;
      final loc = LocationProvider(
        fetcher: () async => (lat: s.lat, lng: s.lng),
      );
      await loc.refresh();
      expect(loc.isReal, isTrue);
      expect(loc.distanceTo(s.lat, s.lng), 0);
    });

    test('a failing fetcher is treated as "no position"', () async {
      final loc = LocationProvider(fetcher: () async => throw Exception('x'));
      await loc.refresh();
      expect(loc.isReal, isFalse);
      expect(loc.loading, isFalse);
    });
  });

  group('AI prompt: shops', () {
    test('shop facts with distances, price and stock, marked as demo', () {
      final stores = StoreContext(
        located: true,
        nearest: [
          for (final s in StoreData.stores.take(2))
            StoreInfo(
              id: 1,
              name: s.name,
              chain: s.chain,
              address: s.address,
              hours: s.hours,
              lat: s.lat,
              lng: s.lng,
              source: s.source,
              distanceM: 800,
            ),
        ],
        offers: {
          12: [
            _offer(qty: 2).withDistance(800),
            _offer(inStock: false, qty: 0).withDistance(2400),
          ],
        },
      );
      final text = AssistantService.shopsForTest(stores, shareProfile: true);
      expect(text, contains('Nearest shops to the user'));
      expect(text, contains('800 m'));
      expect(text, contains('2.4 km'));
      expect(text, contains('few left (2 pcs)'));
      expect(text, contains('out of stock'));
      expect(text, isNot(contains('[demo data]')));
      expect(text, contains('пр. Сарыарка, 15'));
    });

    test('without consent no distances are sent', () {
      final stores = StoreContext(
        located: true,
        nearest: [
          StoreInfo(
            id: 1,
            name: 'Диона',
            chain: 'Диона',
            address: 'пр. Сарыарка, 15',
            hours: '',
            lat: 51.1,
            lng: 71.4,
            source: '',
            distanceM: 800,
          ),
        ],
        offers: const {},
      );
      final text = AssistantService.shopsForTest(stores, shareProfile: false);
      expect(text, isNot(contains('800 m')));
      expect(text, contains('do not state distances'));
    });
  });

  group('test: skipping questions and the photo', () {
    test('few answers make the result weak', () {
      expect(
        ColorTestService.compute(
          warm: 2,
          depth: 1,
          vein: 0,
          answered: 2,
          veinAnswered: false,
        ).isWeak,
        isTrue,
      );
      expect(
        ColorTestService.compute(
          warm: 2,
          depth: 1,
          vein: 3,
          answered: 4,
        ).isWeak,
        isFalse,
      );
      expect(const ColorTestResult.unknown().isWeak, isTrue);
      expect(const ColorTestResult.unknown().answered, 0);
    });

    test('a short test is not biased to "light"', () {
      // 4 of 8 answers, all "deep and warm": scaled up, still Осень
      final r = ColorTestService.compute(
        warm: 4,
        depth: 4,
        vein: 3,
        answered: 4,
      );
      expect(r.colorType, 'Осень');
      expect(r.answered, 5);
    });

    test('the last vein option is "not sure"', () {
      expect(ColorTestService.veinQuestion.length, 4);
      expect(ColorTestService.veinSkipIndex, 3);
      expect(ColorTestService.veinQuestion[3].$4, 0);
    });

    test('weak questionnaire: nothing is guessed, the photo decides', () {
      const weak = ColorTestResult.unknown();
      // no photo: no colour type, the caller must not save it
      final none = BeautyTestFlow.build(
        color: weak,
        skinType: SkinType.dry,
        concerns: const {},
      );
      expect(none.profile.colorType, isNull);
      expect(none.profile.undertone, isNull);
      // a confident photo fills everything
      final withPhoto = BeautyTestFlow.build(
        color: weak,
        skinType: SkinType.dry,
        concerns: const {SkinConcern.dryness},
        vision: const VisionAnalysis(
          colorType: ColorType.winter,
          undertone: Undertone.cool,
          skinTone: SkinTone.light,
          confidence: 0.8,
        ),
      );
      expect(withPhoto.profile.colorType, ColorType.winter);
      expect(withPhoto.profile.undertone, Undertone.cool);
      expect(withPhoto.profile.skinTone, SkinTone.light);
      expect(withPhoto.profile.skinType, SkinType.dry); // from the answers
      expect(withPhoto.photoUsed, isTrue);
      // the model's self-reported number is not carried into the profile
      expect(withPhoto.profile.confidence, isNull);
      // an unsure photo changes nothing
      final unsure = BeautyTestFlow.build(
        color: weak,
        skinType: SkinType.dry,
        concerns: const {},
        vision: const VisionAnalysis(
          colorType: ColorType.winter,
          confidence: 0.3,
        ),
      );
      expect(unsure.profile.colorType, isNull);
    });

    test('a solid questionnaire still wins over the photo', () {
      const solid = ColorTestResult(
        colorType: 'Лето',
        undertone: 'Холодный',
        skinTone: 'Светлый',
      );
      final m = BeautyTestFlow.build(
        color: solid,
        skinType: SkinType.normal,
        concerns: const {},
        vision: const VisionAnalysis(
          colorType: ColorType.autumn,
          undertone: Undertone.warm,
          confidence: 0.9,
        ),
      );
      expect(m.profile.colorType, ColorType.summer);
      expect(m.profile.undertone, Undertone.cool);
    });

    test('a neutral undertone is replaced by a confident photo', () {
      final q = BeautyProfile.fromLabels(
        colorType: 'Весна',
        undertone: 'Нейтральный',
      );
      final m = BeautyProfileMerger.merge(
        q,
        const VisionAnalysis(undertone: Undertone.warm, confidence: 0.9),
      );
      expect(m.profile.undertone, Undertone.warm);
    });

    testWidgets('every question can be skipped; nothing answered goes on', (
      t,
    ) async {
      t.view.physicalSize = const Size(1080, 2200);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final helper = DatabaseHelper(path: inMemoryDatabasePath);
      addTearDown(() => t.runAsync(helper.close));
      RouteSettings? pushed;
      await t.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => NavProvider()),
            ChangeNotifierProvider(
              create: (_) => CartProvider(CartRepository(helper)),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const ColorTestScreen(),
            onGenerateRoute: (s) {
              pushed = s;
              return MaterialPageRoute<void>(
                settings: s,
                builder: (_) => const Scaffold(),
              );
            },
          ),
        ),
      );
      expect(find.text('Шаг 1 из 8'), findsOneWidget);
      // the photo shortcut is offered on the first step
      expect(
        find.text('Не знаете ответов? ИИ определит цветотип по фото за вас'),
        findsOneWidget,
      );
      for (var i = 0; i < 8; i++) {
        await t.tap(find.text('Не знаю — пропустить'));
        await t.pumpAndSettle();
      }
      expect(pushed?.name, AppRoutes.undertoneTest);
      final args = pushed!.arguments! as UndertoneArgs;
      expect(args.answered, 0);
      expect(args.warm, 0);
      expect(args.depth, 0);
    });

    testWidgets('answers count, skipped ones add nothing', (t) async {
      t.view.physicalSize = const Size(1080, 2200);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final helper = DatabaseHelper(path: inMemoryDatabasePath);
      addTearDown(() => t.runAsync(helper.close));
      RouteSettings? pushed;
      await t.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => NavProvider()),
            ChangeNotifierProvider(
              create: (_) => CartProvider(CartRepository(helper)),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const ColorTestScreen(),
            onGenerateRoute: (s) {
              pushed = s;
              return MaterialPageRoute<void>(
                settings: s,
                builder: (_) => const Scaffold(),
              );
            },
          ),
        ),
      );
      // step 1: answer (blue eyes), the rest: skip
      await t.tap(find.text('Голубые / серые'));
      await t.tap(find.text('Далее'));
      await t.pumpAndSettle();
      for (var i = 0; i < 7; i++) {
        await t.tap(find.text('Не знаю — пропустить'));
        await t.pumpAndSettle();
      }
      final args = pushed!.arguments! as UndertoneArgs;
      expect(args.answered, 1);
      expect(args.warm, -1); // only the eyes counted
      expect(args.depth, -1);
    });
  });

  group('palettes', () {
    test('every colour type has a full palette', () {
      for (final t in ColorType.values) {
        final p = ColorPalettes.seasons[t]!;
        expect(p.groups.length, 5, reason: t.code);
        expect(p.groups.map((g) => g.title), [
          'Помада и тинты',
          'Румяна',
          'Тени для век',
          'Одежда и аксессуары',
          'Металл украшений',
        ]);
        expect(p.all.length, greaterThanOrEqualTo(22), reason: t.code);
        expect(p.avoid.length, greaterThanOrEqualTo(4), reason: t.code);
        // makeup colours = the first three groups
        expect(
          p.flattering.length,
          p.groups.take(3).fold<int>(0, (n, g) => n + g.colors.length),
        );
      }
    });

    test('winter has real winter colours', () {
      final names = ColorPalettes.seasons[ColorType.winter]!.all.map(
        (c) => c.name,
      );
      expect(
        names,
        containsAll([
          'Истинный красный',
          'Изумруд',
          'Королевский синий',
          'Чисто-белый',
          'Ледяной голубой',
          'Серебро',
        ]),
      );
      // and not the warm ones
      expect(names, isNot(contains('Персиковый')));
      expect(names, isNot(contains('Золото')));
    });

    test('warm types wear gold, cool types silver', () {
      List<String> metals(ColorType t) => ColorPalettes
          .seasons[t]!
          .groups
          .last
          .colors
          .map((c) => c.name)
          .toList();
      expect(metals(ColorType.spring), contains('Жёлтое золото'));
      expect(metals(ColorType.autumn), contains('Золото'));
      expect(metals(ColorType.summer), contains('Серебро'));
      expect(metals(ColorType.winter), contains('Серебро'));
    });
  });

  group('shops screen', () {
    testWidgets('a product: nearest first, stock status, demo note', (t) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      StoresMapScreen.defaultShowTiles = false;
      addTearDown(() => StoresMapScreen.defaultShowTiles = true);
      final helper = DatabaseHelper(path: inMemoryDatabasePath);
      addTearDown(() => t.runAsync(helper.close));
      // the user stands at the first shop
      final first = StoreData.stores.first;
      await t.pumpWidget(
        CosmetixApp(
          helper: helper,
          locationFetcher: () async => (lat: first.lat, lng: first.lng),
        ),
      );
      await pumpUntil(t, find.text('Добро пожаловать'));
      await t.enterText(find.byType(TextFormField).at(0), SeedData.demoEmail);
      await t.enterText(
        find.byType(TextFormField).at(1),
        SeedData.demoPassword,
      );
      await t.tap(find.byType(ElevatedButton).first);
      await pumpUntil(
        t,
        find.byType(BottomNavigationBar).evaluate().isEmpty
            ? find.byIcon(Icons.home_rounded)
            : find.byType(BottomNavigationBar),
      );
      final ctx = t.element(find.byType(Scaffold).first);
      Navigator.of(
        ctx,
      ).pushNamed(AppRoutes.stores, arguments: const StoresArgs(productId: 12));
      for (var i = 0; i < 10; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Где купить'), findsOneWidget);
      // no demo note: the offers on the screen are verified ones
      expect(
        find.textContaining('цены и наличие демонстрационные'),
        findsNothing,
      );
      expect(
        find.text('Расстояния считаются от вашего положения'),
        findsOneWidget,
      );
      // the first shop is at the user's position: 0 m, listed first
      expect(find.text('Диона'), findsWidgets);
      expect(find.textContaining('0 м от вас'), findsWidgets);
      expect(find.text('демо-данные'), findsNothing);
      // filter by chain: only that chain's shops stay in the list
      expect(find.text('Диона'), findsWidgets);
      await t.tap(
        find.descendant(
          of: find.byType(AppChip),
          matching: find.text('MonAmie'),
        ),
      );
      await t.pump(const Duration(milliseconds: 200));
      expect(find.text('MonAmie'), findsAtLeastNWidgets(2)); // chip + cards
      expect(find.text('Диона'), findsNothing); // other chains are gone
      final loc = Provider.of<LocationProvider>(
        t.element(find.byType(Scaffold).first),
        listen: false,
      );
      expect(loc.isReal, isTrue);
    });
  });
}
