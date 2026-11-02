import 'dart:math' show pow;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/app.dart';
import 'package:cosmetix/core/i18n/translations_en.dart';
import 'package:cosmetix/core/i18n/translations_kk.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/providers/cart_provider.dart';
import 'package:cosmetix/providers/catalog_provider.dart';
import 'package:cosmetix/repositories/care_repository.dart';
import 'package:cosmetix/repositories/cart_repository.dart';
import 'package:cosmetix/repositories/product_repository.dart';
import 'package:cosmetix/repositories/safety_repository.dart';
import 'package:cosmetix/repositories/user_repository.dart';
import 'package:cosmetix/services/recommendation_service.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/routes/route_args.dart';
import 'package:cosmetix/screens/stores/stores_map_screen.dart';
import 'widget_test.dart' show pumpUntil;

double _lum(Color c) {
  double f(double v) =>
      v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
}

double _contrast(Color a, Color b) {
  final la = _lum(a);
  final lb = _lum(b);
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('grey and pink text read on the powder-pink surfaces (4.5:1)', () {
    const pal = AppPalette.light;
    expect(_contrast(pal.subtext, AppColors.primarySoft), greaterThan(4.5));
    expect(_contrast(pal.subtext, AppColors.blush), greaterThan(4.5));
    expect(_contrast(pal.subtext, pal.surface), greaterThan(4.5));
    expect(_contrast(pal.accent, AppColors.primarySoft), greaterThan(4.5));
    expect(_contrast(pal.accent, AppColors.saleSoft), greaterThan(4.5));
    const dark = AppPalette.dark;
    expect(_contrast(dark.subtext, dark.surface), greaterThan(4.5));
    expect(_contrast(dark.accent, dark.surface), greaterThan(4.5));
  });

  group('shades of one line', () {
    late DatabaseHelper helper;
    late List<Product> all;
    late CatalogProvider catalog;

    setUp(() async {
      helper = DatabaseHelper(path: inMemoryDatabasePath);
      all = await ProductRepository(helper).getAll(1);
      final repo = ProductRepository(helper);
      catalog = CatalogProvider(
        repo,
        RecommendationService(
          repo,
          SafetyRepository(helper),
          UserRepository(helper),
          CareRepository(helper),
        ),
      );
      catalog.products = all;
    });
    tearDown(() => helper.close());

    Product byName(String part) => all.firstWhere((p) => p.name.contains(part));

    test('the palettes 00, 01, 02, 03, 05 and 07 are one line', () {
      final five = byName('Palette 05');
      final shades = catalog.shadesOf(five);
      // all of them, the product itself included, by number
      expect(shades.map(CatalogProvider.shadeNumber), [
        '00',
        '01',
        '02',
        '03',
        '05',
        '07',
      ]);
      expect(shades.map((p) => p.id), contains(five.id));
      // from any shade the same line is found
      expect(
        catalog.shadesOf(byName('Palette 01')).map((p) => p.id),
        shades.map((p) => p.id),
      );
      expect(catalog.listName(five), 'Better Than Palette');
      expect(CatalogProvider.shadeName(five), '05 Shade & Shadow Garden');
    });

    test('lists show one tile for the line, not one per shade', () {
      final palettes = all.where((p) => p.name.contains('Better Than Palette'));
      expect(palettes.length, 6);
      final collapsed = catalog.collapseLines(all);
      expect(
        collapsed.where((p) => p.name.contains('Better Than Palette')).length,
        1,
      );
      // the first one of the given order stays: the best match in a ranking
      final reversed = catalog.collapseLines(all.reversed.toList());
      expect(
        reversed.firstWhere((p) => p.name.contains('Palette')).name,
        'Better Than Palette 07 Berry Fuchsia Garden',
      );
      // products with one shade and without a number stay as they are
      expect(
        collapsed.length,
        all.length - 5 /* palettes */ - 1 /* the second tint */,
      );
      expect(catalog.listName(byName('Better Than Eyes')), 'Better Than Eyes');
    });

    test('tints of a line, and products without a number have no line', () {
      expect(catalog.shadesOf(byName('Glowy Tint 30')).map((p) => p.name), [
        'Ink Mood Glowy Tint 03 Rose In Mind',
        'Ink Mood Glowy Tint 30 Happy Berry',
      ]);
      expect(catalog.shadesOf(byName('Better Than Eyes')), isEmpty);
      expect(catalog.shadesOf(byName('Niacinamide 10%')), isEmpty);
      // a tint that is alone in its line is just a product
      expect(catalog.shadesOf(byName('Juicy Lasting Tint 01')), isEmpty);
      // a different brand with the same words is not the same line
      expect(
        catalog.shadesOf(byName('Palette 00')).any((p) => p.brand != 'Rom&nd'),
        isFalse,
      );
    });

    test('every new makeup product has a shade colour and a photo', () {
      for (final p in all.where((p) => p.name.contains('Palette'))) {
        expect(p.shade, isNotNull, reason: p.name);
        expect(p.art, contains('assets/products/'), reason: p.name);
      }
      expect(all.length, 38);
    });
  });

  group('cart counter', () {
    test('quantityOf and decrease', () async {
      final h = DatabaseHelper(path: inMemoryDatabasePath);
      addTearDown(h.close);
      final products = await ProductRepository(h).getAll(1);
      final cart = CartProvider(CartRepository(h));
      await cart.load(1);
      final p = products.first;
      expect(cart.quantityOf(p.id), 0);
      await cart.decrease(p.id); // nothing in the cart: no error
      expect(await cart.add(p), isNull);
      expect(await cart.add(p), isNull);
      expect(cart.quantityOf(p.id), 2);
      await cart.decrease(p.id);
      expect(cart.quantityOf(p.id), 1);
      await cart.decrease(p.id);
      expect(cart.quantityOf(p.id), 0);
      expect(cart.contains(p.id), isFalse);
    });
  });

  group('screens', () {
    Future<void> boot(
      WidgetTester t,
      DatabaseHelper h, {
      Map<String, Object?> user = const {},
    }) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      addTearDown(() => t.runAsync(h.close));
      if (user.isNotEmpty) {
        await t.runAsync(() async {
          final db = await h.database;
          await db.update('users', user, where: 'id = 1');
        });
      }
      await t.runAsync(() => UserRepository(h).setCurrentUser(1));
      await t.pumpWidget(CosmetixApp(helper: h));
      await pumpUntil(t, find.text('Кабинет'));
      await _settle(t);
    }

    NavigatorState nav(WidgetTester t) =>
        t.state<NavigatorState>(find.byType(Navigator).first);

    testWidgets('the product bar: a big button, then a counter', (t) async {
      final h = DatabaseHelper(path: inMemoryDatabasePath);
      await boot(t, h);
      nav(t).pushNamed(AppRoutes.product, arguments: 12);
      await _settle(t);
      expect(find.text('В корзину'), findsOneWidget);
      await t.tap(find.text('В корзину'));
      await _settle(t);
      // the big button is gone: "1 in the cart" with minus and plus
      expect(find.text('В корзину'), findsNothing);
      expect(find.text('1 в корзине'), findsOneWidget);
      await t.tap(find.byIcon(Icons.add).last);
      await _settle(t);
      expect(find.text('2 в корзине'), findsOneWidget);
      await t.tap(find.byIcon(Icons.remove).last);
      await _settle(t);
      expect(find.text('1 в корзине'), findsOneWidget);
      await t.tap(find.byIcon(Icons.remove).last);
      await _settle(t);
      // the cart is empty again: the button is back
      expect(find.text('В корзину'), findsOneWidget);
      await _settle(t); // let the snack bars go
      await t.pump(const Duration(seconds: 6));
    });

    testWidgets('the profile shows the first letter, a tap tells the word', (
      t,
    ) async {
      final h = DatabaseHelper(path: inMemoryDatabasePath);
      await boot(
        t,
        h,
        user: {
          'skin_type': 'Комбинированная',
          'undertone': 'Нейтральный',
          'color_type': 'Лето',
          'beauty_source': 'questionnaire',
        },
      );
      await t.tap(find.text('Кабинет').last);
      await _settle(t);
      expect(find.text('Лето'), findsOneWidget); // short: stays whole
      expect(find.text('К'), findsOneWidget);
      expect(find.text('Н'), findsOneWidget);
      expect(find.text('Комбинированная'), findsNothing);
      expect(find.text('Нейтральный'), findsNothing);
      await t.tap(find.text('К'));
      await _settle(t);
      expect(find.text('Тип кожи: Комбинированная'), findsOneWidget);
      await t.pump(const Duration(seconds: 6));
    });

    testWidgets('home: whole category names, no composition row in catalog', (
      t,
    ) async {
      final h = DatabaseHelper(path: inMemoryDatabasePath);
      await boot(t, h);
      // pills with the whole word, the row scrolls sideways
      expect(find.text('Макияж'), findsWidgets);
      expect(find.text('Уход за лицом'), findsOneWidget);
      await t.drag(find.text('Макияж').first, const Offset(-500, 0));
      await _settle(t);
      expect(find.text('Тело и ванна'), findsOneWidget);
      nav(t).pushNamed(AppRoutes.catalog);
      await _settle(t);
      // the composition filter lives in "Фильтры"
      expect(find.text('Состав:'), findsNothing);
      expect(find.text('Фильтры'), findsOneWidget);
    });

    testWidgets('the chat: an empty send only puts the keyboard away', (
      t,
    ) async {
      final h = DatabaseHelper(path: inMemoryDatabasePath);
      await boot(t, h);
      await t.tap(find.text('ИИ Чат').last);
      await _settle(t);
      await t.tap(find.byType(TextField));
      await _settle(t);
      expect(FocusManager.instance.primaryFocus?.hasPrimaryFocus, isTrue);
      await t.tap(find.byIcon(Icons.send_rounded));
      await _settle(t);
      expect(find.text('Введите сообщение'), findsNothing);
      // the field lost focus: the keyboard is away
      expect(find.byType(EditableText), findsOneWidget);
      final editable = t.widget<EditableText>(find.byType(EditableText));
      expect(editable.focusNode.hasFocus, isFalse);
      // a tap on the conversation does the same
      await t.tap(find.byType(TextField));
      await _settle(t);
      expect(
        t.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
        isTrue,
      );
      await t.tapAt(const Offset(200, 600));
      await _settle(t);
      expect(
        t.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
        isFalse,
      );
    });

    testWidgets('the map goes full screen and comes back', (t) async {
      StoresMapScreen.defaultShowTiles = false; // no Internet in tests
      addTearDown(() => StoresMapScreen.defaultShowTiles = true);
      final h = DatabaseHelper(path: inMemoryDatabasePath);
      await boot(t, h);
      nav(t).pushNamed(AppRoutes.stores);
      await _settle(t);
      expect(find.byIcon(Icons.fullscreen), findsOneWidget);
      await t.tap(find.byIcon(Icons.fullscreen));
      await _settle(t);
      expect(find.byIcon(Icons.fullscreen_exit), findsOneWidget);
      expect(find.byIcon(Icons.my_location), findsWidgets);
      // the page chrome (title bar) is gone: the map has the whole screen
      expect(find.text('Магазины рядом'), findsNothing);
      await t.tap(find.byIcon(Icons.fullscreen_exit));
      await _settle(t);
      expect(find.byIcon(Icons.fullscreen), findsOneWidget);
      expect(find.text('Магазины рядом'), findsOneWidget);
    });

    testWidgets('a palette is one product with a circle for every shade', (
      t,
    ) async {
      final h = DatabaseHelper(path: inMemoryDatabasePath);
      await boot(t, h);
      // the catalog: one tile for the whole palette line
      nav(t).pushNamed(
        AppRoutes.catalog,
        arguments: const CatalogArgs(query: 'Palette'),
      );
      await _settle(t);
      expect(find.text('Better Than Palette'), findsOneWidget);
      expect(find.textContaining('Better Than Palette 0'), findsNothing);
      nav(t).pop();
      await _settle(t);

      final id =
          (await t.runAsync(() async {
                final db = await h.database;
                return (await db.query(
                  'products',
                  where: "name LIKE 'Better Than Palette 05%'",
                )).single['id']!;
              }))!
              as int;
      nav(t).pushNamed(AppRoutes.product, arguments: id);
      await _settle(t);
      // the line as the title, the chosen shade under it, a circle per shade
      expect(find.text('Better Than Palette'), findsOneWidget);
      expect(find.text('Оттенок: 05 Shade & Shadow Garden'), findsOneWidget);
      for (final n in ['00', '01', '02', '03', '05', '07']) {
        expect(find.text(n), findsOneWidget, reason: n);
      }
      // no separate cards of the same palette any more
      expect(find.text('Другие оттенки'), findsNothing);
      // a tap on a circle: the same page for that shade
      await t.tap(find.text('02'));
      await _settle(t);
      expect(find.text('Оттенок: 02 Mahogany Garden'), findsOneWidget);
      expect(find.text('Better Than Palette'), findsOneWidget);
      await t.pump(const Duration(seconds: 1));
    });
  });

  test('every new string is translated (EN and KK)', () {
    for (final k in [
      'Убрать одну',
      'Добавить ещё',
      '{v0} в корзине',
      'Карта на весь экран',
      'Свернуть карту',
      'Моё положение',
      'Из чёрного списка ничего не найдено',
      'Проверено компонентов: {n}',
      '{v0}: найдено ({v1})',
      '{v0}: не найдено',
      'Оттенок: {v0}',
    ]) {
      expect(translationsEn[k], isNotNull, reason: 'EN: $k');
      expect(translationsKk[k], isNotNull, reason: 'KK: $k');
      for (final ph in RegExp(r'\{\w+\}').allMatches(k).map((m) => m[0]!)) {
        expect(translationsEn[k], contains(ph), reason: 'EN $ph in $k');
        expect(translationsKk[k], contains(ph), reason: 'KK $ph in $k');
      }
    }
  });
}
