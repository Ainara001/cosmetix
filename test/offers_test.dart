import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/app.dart';
import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/theme/app_theme.dart';
import 'package:cosmetix/core/utils/formatters.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/models/store_offer.dart';
import 'package:cosmetix/repositories/offer_repository.dart';
import 'package:cosmetix/repositories/product_repository.dart';
import 'package:cosmetix/repositories/user_repository.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/routes/route_args.dart';
import 'package:cosmetix/services/source_policy.dart';
import 'package:cosmetix/widgets/offer_widgets.dart';
import 'widget_test.dart' show pumpUntil;

/// Honest prices: only verified shop offers are shown, with their date; the
/// demo values of the seed are not shown as prices.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // a real install has no verified offers: switch the test fixture off
  final saved = DatabaseHelper.afterSeed;
  setUp(() => DatabaseHelper.afterSeed = null);
  tearDown(() => DatabaseHelper.afterSeed = saved);

  const productId = 12; // The Ordinary Niacinamide
  const storeId = 2;

  OfferInput offer({
    int? price = 5600,
    int? oldPrice,
    Availability availability = Availability.inStock,
    String? url,
    UrlKind kind = UrlKind.none,
    DateTime? at,
    bool verified = true,
    String source = 'shelf price, shop visit',
    String method = OfferMethod.manualVisit,
    int product = productId,
  }) => OfferInput(
    productId: product,
    storeId: storeId,
    price: price,
    oldPrice: oldPrice,
    availability: availability,
    url: url,
    urlKind: kind,
    source: source,
    method: method,
    checkedAt: at ?? DateTime.now(),
    verified: verified,
  );

  group('the validated offer', () {
    test('a complete offer is accepted', () {
      offer(
        oldPrice: 7000,
        url: 'https://shop.example/p/1',
        kind: UrlKind.product,
      ).validate();
    });

    for (final c in <String, OfferInput Function()>{
      'no source': () => offer(source: '  '),
      'an unknown method': () => offer(method: 'guess'),
      'a zero price': () => offer(price: 0),
      'an old price below the price': () => offer(oldPrice: 5000),
      'an old price without a price': () => offer(price: null, oldPrice: 100),
      'a link without its kind': () => offer(url: 'https://shop.example/p'),
      'a kind without a link': () => offer(kind: UrlKind.product),
      'a link that is not http(s)': () =>
          offer(url: 'javascript:alert(1)', kind: UrlKind.product),
      'a check time in the future': () =>
          offer(at: DateTime.now().add(const Duration(days: 2))),
      'a verified offer that says nothing': () =>
          offer(price: null, availability: Availability.unknown),
    }.entries) {
      test('refuses ${c.key}', () {
        expect(() => c.value().validate(), throwsFormatException);
      });
    }

    test('a link-only offer is fine when the link opens the product', () {
      offer(
        price: null,
        availability: Availability.unknown,
        url: 'https://shop.example/p/1',
        kind: UrlKind.product,
      ).validate();
    });
  });

  group('the table (v17)', () {
    late DatabaseHelper h;
    late OfferRepository repo;
    setUp(() async {
      h = DatabaseHelper(path: inMemoryDatabasePath);
      await h.database;
      repo = OfferRepository(h);
    });
    tearDown(() => h.close());

    test('a fresh install has no offer at all', () async {
      expect(await (await h.database).query('store_offers'), isEmpty);
      expect(DatabaseHelper.dbVersion, 18);
    });

    test(
      'one offer per product and shop: a second replaces the first',
      () async {
        await repo.save(offer(price: 5600));
        await repo.save(offer(price: 5300));
        final all = await repo.forProduct(productId);
        expect(all, hasLength(1));
        expect(all.single.price, 5300);
      },
    );

    test('unverified offers are kept but not returned as verified', () async {
      await repo.save(offer(verified: false));
      expect(await repo.forProduct(productId), isEmpty);
      expect(
        await repo.forProduct(productId, onlyVerified: false),
        hasLength(1),
      );
      final prices = await ProductRepository(h).getStorePrices(productId);
      expect(prices, isEmpty);
      final p = (await ProductRepository(h).getById(productId, 1))!;
      expect(p.hasPrice, isFalse);
    });

    test('the database itself refuses what validation refuses', () async {
      final db = await h.database;
      Future<void> raw(Map<String, Object?> extra) =>
          db.insert('store_offers', {
            'product_id': productId,
            'store_id': storeId,
            'source': 's',
            'method': 'manual_visit',
            'checked_at': 1,
            ...extra,
          });
      await expectLater(raw({'price': 0}), throwsA(anything));
      await expectLater(raw({'method': 'scrape'}), throwsA(anything));
      await expectLater(raw({'availability': 'maybe'}), throwsA(anything));
      await expectLater(raw({'source': ' '}), throwsA(anything));
      await expectLater(
        raw({'url': 'ftp://x', 'url_kind': 'product'}),
        throwsA(anything),
      );
      await expectLater(raw({'url_kind': 'product'}), throwsA(anything));
      await expectLater(
        raw({'verification': 'verified'}),
        throwsA(anything),
        reason: 'verified without a price, stock or product link',
      );
    });

    test('deleting a product removes its offers', () async {
      await repo.save(offer());
      await (await h.database).delete(
        'products',
        where: 'id = ?',
        whereArgs: [productId],
      );
      expect(await (await h.database).query('store_offers'), isEmpty);
    });

    test('the price of a product is its lowest verified shop price', () async {
      await repo.save(offer(price: 5600, oldPrice: 7000));
      await OfferRepository(h).save(
        OfferInput(
          productId: productId,
          storeId: 3,
          price: 5200,
          availability: Availability.outOfStock,
          source: 'site, checked by hand',
          method: OfferMethod.manualSite,
          checkedAt: DateTime.now(),
        ),
      );
      final p = (await ProductRepository(h).getById(productId, 1))!;
      expect(p.price, 5200);
      expect(p.availability, Availability.inStock, reason: 'one shop has it');
      expect(p.priceCheckedAt, isNotNull);
    });
  });

  group('the screens', () {
    Future<DatabaseHelper> boot(
      WidgetTester t, {
      List<OfferInput> offers = const [],
    }) async {
      t.view.physicalSize = const Size(1080, 4200);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final h = DatabaseHelper(path: inMemoryDatabasePath);
      addTearDown(() => t.runAsync(h.close));
      await t.runAsync(() async {
        await h.database;
        for (final o in offers) {
          await OfferRepository(h).save(o);
        }
        await UserRepository(h).setCurrentUser(1);
      });
      await t.pumpWidget(CosmetixApp(helper: h));
      await pumpUntil(t, find.text('Кабинет'));
      await settle(t, 6);
      return h;
    }

    Future<void> open(WidgetTester t, String route, [Object? args]) async {
      t
          .state<NavigatorState>(find.byType(Navigator).first)
          .pushNamed(route, arguments: args);
      await settle(t, 10);
    }

    testWidgets(
      'a product with no verified offer shows no price and no stock',
      (t) async {
        await boot(t);
        await open(t, AppRoutes.product, productId);
        expect(find.byKey(const Key('no-offers')), findsOneWidget);
        expect(find.text('Цена не подтверждена'), findsWidgets);
        expect(find.text('Наличие не проверено'), findsWidgets);
        expect(find.text('В НАЛИЧИИ'), findsNothing);
        expect(
          find.textContaining(Formatters.price(5600)),
          findsNothing,
          reason: 'the demo price',
        );
        expect(find.text('демо-данные'), findsNothing);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('a fresh verified offer shows the price and its date', (
      t,
    ) async {
      await boot(t, offers: [offer(price: 5100, oldPrice: 6000)]);
      await open(t, AppRoutes.product, productId);
      expect(find.byKey(const Key('no-offers')), findsNothing);
      expect(find.textContaining(Formatters.price(5100)), findsWidgets);
      expect(find.byKey(const Key('offer-fresh')), findsWidgets);
      expect(
        find.textContaining(
          'Проверено ${offerDate(DateTime.now().millisecondsSinceEpoch)}',
        ),
        findsWidgets,
      );
      expect(find.text('В НАЛИЧИИ'), findsOneWidget);
    });

    testWidgets('an old price says it is the price at the last check', (
      t,
    ) async {
      final old = DateTime.now().subtract(const Duration(days: 20));
      await boot(t, offers: [offer(price: 5100, at: old)]);
      await open(t, AppRoutes.product, productId);
      expect(find.byKey(const Key('offer-stale')), findsWidgets);
      expect(
        find.text(
          'Цена на момент последней проверки: ${offerDate(old.millisecondsSinceEpoch)}',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Цена на ${offerDate(old.millisecondsSinceEpoch)}'),
        findsOneWidget,
        reason: 'the price bar says it in short',
      );
      expect(find.byKey(const Key('offer-fresh')), findsNothing);
    });

    testWidgets('a card without a verified price says so, not a number', (
      t,
    ) async {
      await boot(t);
      await open(t, AppRoutes.catalog, const CatalogArgs(query: 'Niacinamide'));
      expect(find.text('Цена не подтверждена'), findsWidgets);
      expect(find.textContaining(RegExp(r'\d \d{3}\s?тг')), findsNothing);
    });

    testWidgets('the cart keeps working and shows no made-up amount', (
      t,
    ) async {
      await boot(t);
      await open(t, AppRoutes.product, productId);
      await t.tap(find.text('В корзину'));
      await settle(t, 6);
      nav(t).pop();
      await settle(t, 4);
      await t.tap(find.text('Корзина').last);
      await settle(t, 6);
      expect(find.text('Цена не подтверждена'), findsWidgets);
      expect(find.textContaining(RegExp(r'\d \d{3}\s?тг')), findsNothing);
    });
  });

  group('links to a shop', () {
    StorePrice priced({
      String? url,
      UrlKind kind = UrlKind.product,
      String chain = 'Диона',
    }) => StorePrice(
      storeId: 7,
      storeName: 'Диона',
      distanceM: 100,
      address: 'A',
      rating: 0,
      price: 1000,
      inStock: true,
      chain: chain,
      url: url,
      urlKind: kind,
    );

    Future<void> pump(WidgetTester t, StorePrice o, SourcePolicy p) =>
        t.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: OfferLink(offer: o, policy: p),
            ),
          ),
        );

    testWidgets('no link is shown unless the shop is allowed', (t) async {
      await pump(
        t,
        priced(url: 'https://shop.example/p/1'),
        const SourcePolicy.of({}),
      );
      expect(find.byType(TextButton), findsNothing);
      await pump(
        t,
        priced(url: 'https://shop.example/p/1'),
        const SourcePolicy.of({'Диона': 'unconfirmed'}),
      );
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('an allowed shop opens exactly the stored address', (t) async {
      Uri? opened;
      OfferLink.launcher = (u) async {
        opened = u;
        return true;
      };
      await pump(
        t,
        priced(url: 'https://shop.example/p/1'),
        const SourcePolicy.of({'Диона': 'allowed'}),
      );
      expect(find.text('Посмотреть товар в магазине'), findsOneWidget);
      await t.tap(find.byType(TextButton));
      expect(opened.toString(), 'https://shop.example/p/1');
    });

    testWidgets('a search link says it is a search', (t) async {
      await pump(
        t,
        priced(url: 'https://shop.example/s?q=x', kind: UrlKind.search),
        const SourcePolicy.of({'Диона': 'allowed'}),
      );
      expect(find.text('Поиск в магазине'), findsOneWidget);
      expect(find.text('Посмотреть товар в магазине'), findsNothing);
    });

    testWidgets('no link, no button', (t) async {
      await pump(
        t,
        priced(kind: UrlKind.none),
        const SourcePolicy.of({'Диона': 'allowed'}),
      );
      expect(find.byType(TextButton), findsNothing);
    });

    test('the bundled policy allows no shop yet', () {
      final p = SourcePolicy.parse(
        '{"default":{"links":"unconfirmed"},"shops":{"Золотое Яблоко":{"links":"unconfirmed"}}}',
      );
      expect(p.linksAllowed('Золотое Яблоко'), isFalse);
      expect(p.linksAllowed('Какой-то магазин'), isFalse);
    });
  });

  test('every new string is translated', () {
    for (final k in [
      'Цена не подтверждена',
      'Наличие не проверено',
      'Посмотреть товар в магазине',
      'Поиск в магазине',
      'Проверено {d}',
      'Цена на момент последней проверки: {d}',
    ]) {
      currentLang = AppLang.en;
      expect(tr(k), isNot(k), reason: 'EN: $k');
      currentLang = AppLang.kk;
      expect(tr(k), isNot(k), reason: 'KK: $k');
    }
    currentLang = AppLang.ru;
  });
}

Future<void> settle(WidgetTester t, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await t.pump(const Duration(milliseconds: 120));
  }
}

NavigatorState nav(WidgetTester t) =>
    t.state<NavigatorState>(find.byType(Navigator).first);
