import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/app.dart';
import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/i18n/translations_catalog.dart';
import 'package:cosmetix/core/theme/app_theme.dart';
import 'package:cosmetix/database/catalog_data.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/models/palette_models.dart';
import 'package:cosmetix/providers/settings_provider.dart';
import 'package:cosmetix/repositories/user_repository.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/routes/route_args.dart';
import 'package:cosmetix/screens/product/palette_section.dart';
import 'package:cosmetix/widgets/pill_segments.dart';
import 'package:cosmetix/widgets/shade_widgets.dart';
import 'widget_test.dart' show pumpUntil;

/// Palette variants, cells and the note about approximate colours on the
/// product screens and in the lists.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late CatalogData catalog;
  setUpAll(() async => catalog = await CatalogData.load());
  int idOf(String name) =>
      catalog.products.indexWhere((p) => p.name == name) + 1;
  final p02 = 'Better Than Palette 02 Mahogany Garden';

  Future<void> settle(WidgetTester t, [int n = 10]) async {
    for (var i = 0; i < n; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await t.pump(const Duration(milliseconds: 120));
    }
  }

  Future<DatabaseHelper> boot(
    WidgetTester t, {
    Size size = const Size(1080, 4200),
    double dpr = 3,
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = dpr;
    addTearDown(t.view.reset);
    final h = DatabaseHelper(path: inMemoryDatabasePath);
    addTearDown(() => t.runAsync(h.close));
    await t.runAsync(() => UserRepository(h).setCurrentUser(1));
    await t.pumpWidget(CosmetixApp(helper: h));
    await pumpUntil(t, find.text('Кабинет'));
    await settle(t, 8);
    return h;
  }

  NavigatorState nav(WidgetTester t) =>
      t.state<NavigatorState>(find.byType(Navigator).first);

  Future<void> open(WidgetTester t, String route, [Object? args]) async {
    nav(t).pushNamed(route, arguments: args);
    await settle(t);
  }

  group('the building blocks', () {
    Widget host(Widget child, {ThemeData? theme, double width = 320}) =>
        MaterialApp(
          theme: theme ?? AppTheme.light(),
          home: Scaffold(
            body: Center(
              child: SizedBox(width: width, child: child),
            ),
          ),
        );

    testWidgets('an unknown colour is a neutral cell that says so', (t) async {
      await t.pumpWidget(host(const PanCell(position: 3)));
      expect(find.text('3'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Ячейка 3, цвет не измерен'),
        findsOneWidget,
      );
    });

    testWidgets('a grid of ten cells fits a 320 px screen at text scale 1.3', (
      t,
    ) async {
      t.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      final pans = [
        for (var i = 1; i <= 10; i++)
          PalettePan(
            key: 'x/$i',
            productId: 1,
            position: i,
            name: null,
            finish: null,
            colour: null,
            colourStatus: 'missing',
            colourSource: null,
          ),
      ];
      await t.pumpWidget(host(PanGrid(pans: pans), width: 288));
      expect(find.byType(PanCell), findsNWidgets(10));
      expect(t.takeException(), isNull);
      // five in a row: two rows
      final tops = {
        for (final e in find.byType(PanCell).evaluate())
          t.getTopLeft(find.byWidget(e.widget)).dy.round(),
      };
      expect(tops, hasLength(2));
    });

    testWidgets('only a cell with a known colour can be chosen', (t) async {
      final chosen = <String>[];
      final pans = [
        const PalettePan(
          key: 'a',
          productId: 1,
          position: 1,
          name: null,
          finish: null,
          colour: null,
          colourStatus: 'missing',
          colourSource: null,
        ),
        const PalettePan(
          key: 'b',
          productId: 1,
          position: 2,
          name: null,
          finish: null,
          colour: Color(0xFF8A4B3C),
          colourStatus: 'measured_swatch',
          colourSource: 'test',
        ),
      ];
      await t.pumpWidget(
        host(PanGrid(pans: pans, onSelect: (p) => chosen.add(p.key))),
      );
      await t.tap(find.byKey(const Key('pan-a')));
      await t.tap(find.byKey(const Key('pan-b')));
      expect(chosen, ['b']);
    });

    testWidgets('pill segments choose one and work in the dark theme', (
      t,
    ) async {
      var value = 1;
      await t.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, set) => PillSegments<int>(
              segments: const [
                PillSegment(value: 1, label: 'Один'),
                PillSegment(value: 2, label: 'Два', icon: Icons.brush),
              ],
              selected: value,
              onChanged: (v) => set(() => value = v),
            ),
          ),
          theme: AppTheme.dark(),
        ),
      );
      await t.tap(find.text('Два'));
      await t.pump();
      expect(value, 2);
      expect(t.takeException(), isNull);
    });

    test('the note has one standard wording', () {
      expect(ApproxNote.standard, 'Приблизительная передача оттенка');
    });
  });

  group('the product page of a palette', () {
    testWidgets('shows the variants, ten grey cells and the approximate note', (
      t,
    ) async {
      await boot(t);
      await open(t, AppRoutes.product, idOf(p02));
      expect(find.byKey(const Key('palette-section')), findsOneWidget);
      expect(find.text('Вариант палетки: 02 Mahogany Garden'), findsOneWidget);
      for (final id in [
        idOf('Better Than Palette 00 Light & Glitter Garden'),
        idOf('Better Than Palette 01 Pampas Garden'),
        idOf(p02),
        idOf('Better Than Palette 03 Rosebud Garden'),
        idOf('Better Than Palette 05 Shade & Shadow Garden'),
        idOf('Better Than Palette 07 Berry Fuchsia Garden'),
      ]) {
        expect(find.byKey(Key('variant-$id')), findsOneWidget);
      }
      // the pills are as wide as their text, not stretched over the row
      expect(
        t.getSize(find.byKey(Key('variant-${idOf(p02)}'))).width,
        lessThan(100),
      );
      // ten cells: two rows of five
      final tops = {
        for (final e in find.byType(PanCell).evaluate())
          t.getTopLeft(find.byWidget(e.widget)).dy.round(),
      };
      expect(tops, hasLength(2));
      expect(find.text('Цвета внутри палетки: 10'), findsOneWidget);
      expect(find.byType(PanCell), findsNWidgets(10));
      // no cell has a colour: the cells are neutral, nothing is invented
      for (final c in t.widgetList<PanCell>(find.byType(PanCell))) {
        expect(c.colour, isNull);
      }
      expect(find.byKey(const Key('palette-cells-note')), findsOneWidget);
      // the old per-variant colour circles are not there
      expect(find.textContaining('Оттенок: 02'), findsNothing);
      // the try-on is off, with its reason, and no colour is claimed
      expect(find.byKey(const Key('try-on-button')), findsNothing);
      expect(find.byKey(const Key('try-on-button-off')), findsOneWidget);
      expect(find.byKey(const Key('try-on-unavailable')), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('another variant opens the page of that product', (t) async {
      await boot(t);
      await open(t, AppRoutes.product, idOf(p02));
      final id03 = idOf('Better Than Palette 03 Rosebud Garden');
      await t.tap(find.byKey(Key('variant-$id03')));
      await settle(t);
      final section = t.widget<PaletteSection>(find.byType(PaletteSection));
      expect(section.productId, id03);
      expect(find.byType(PanCell), findsNWidgets(10));
      expect(find.text('Вариант палетки: 03 Rosebud Garden'), findsOneWidget);
    });

    testWidgets('"About the data" tells the source, the date and the trust', (
      t,
    ) async {
      await boot(t);
      await open(t, AppRoutes.product, idOf(p02));
      await t.tap(find.byKey(const Key('palette-data-link')));
      await settle(t, 6);
      final sheet = find.byKey(const Key('palette-data-sheet'));
      expect(sheet, findsOneWidget);
      for (final s in [
        'Rom&nd',
        'Better Than Palette',
        '02 Mahogany Garden',
        '10',
        'https://romandbeauty.com/products/better-than-palette',
        '2026-11-05',
        'Страница производителя, ещё не проверено вручную',
      ]) {
        expect(
          find.descendant(of: sheet, matching: find.text(s)),
          findsOneWidget,
          reason: s,
        );
      }
    });

    testWidgets('a measured cell is filled and counted, the note changes', (
      t,
    ) async {
      final h = await boot(t);
      await t.runAsync(() async {
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
      });
      await open(t, AppRoutes.product, idOf(p02));
      final cells = t.widgetList<PanCell>(find.byType(PanCell)).toList();
      expect(cells[2].colour, const Color(0xFF8A4B3C));
      expect(cells[2].approximate, isFalse);
      expect(cells.where((c) => c.colour == null), hasLength(9));
    });

    testWidgets('price, cart and favourite belong to the whole palette', (
      t,
    ) async {
      final h = await boot(t);
      final id = idOf(p02);
      await open(t, AppRoutes.product, id);
      await t.tap(find.text('В корзину'));
      await settle(t, 4);
      await t.tap(find.byIcon(Icons.favorite_border).first);
      await settle(t, 4);
      Future<int> count(String table) => t
          .runAsync(() async {
            final db = await h.database;
            return (await db.rawQuery(
              'SELECT * FROM $table WHERE user_id = 1 AND product_id = ?',
              [id],
            )).length;
          })
          .then((v) => v!);
      expect(await count('cart_items'), 1);
      expect(await count('favorites'), 1);
    });

    testWidgets('a palette whose cells are not confirmed shows no cells', (
      t,
    ) async {
      await boot(t);
      await open(t, AppRoutes.product, idOf('Better Than Eyes'));
      expect(find.byKey(const Key('palette-section')), findsNothing);
      // not a confirmed palette line: nothing about cells is claimed at all
      expect(find.byType(PanCell), findsNothing);
    });

    testWidgets('fits a small phone at large text, light and dark', (t) async {
      t.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await boot(t, size: const Size(640, 1136), dpr: 2);
      await open(t, AppRoutes.product, idOf(p02));
      await t.dragUntilVisible(
        find.byKey(const Key('palette-data-link')),
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      expect(find.byType(PanCell), findsNWidgets(10));
      expect(t.takeException(), isNull);
      await t.tap(
        find.byKey(const Key('palette-data-link')),
        warnIfMissed: false,
      );
      await settle(t, 6);
      expect(t.takeException(), isNull);
      nav(t).pop();
      await settle(t, 4);
      final ctx = t.element(find.byType(Navigator).first);
      await t.runAsync(
        () => ctx.read<SettingsProvider>().setTheme(ThemeMode.dark),
      );
      await settle(t, 8);
      await open(t, AppRoutes.product, idOf(p02));
      await t.dragUntilVisible(
        find.byKey(const Key('palette-data-link')),
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      expect(find.byType(PanCell), findsNWidgets(10));
      expect(t.takeException(), isNull);
    });
  });

  group('lists and other products', () {
    testWidgets('a palette line is one card: variants and colours, no dots', (
      t,
    ) async {
      await boot(t);
      await open(t, AppRoutes.catalog, const CatalogArgs(category: 'Макияж'));
      expect(find.text('Better Than Palette'), findsOneWidget);
      expect(find.text('Вариантов: 6 · цветов: 10'), findsOneWidget);
      expect(find.text('Оттенков: 2'), findsOneWidget); // Ink Mood Glowy Tint
    });

    testWidgets('a lipstick keeps its shade picker and gets the note', (
      t,
    ) async {
      await boot(t);
      await open(
        t,
        AppRoutes.product,
        idOf('Ink Mood Glowy Tint 30 Happy Berry'),
      );
      expect(find.byKey(const Key('palette-section')), findsNothing);
      expect(find.textContaining('Оттенок: 30 Happy Berry'), findsOneWidget);
      expect(find.byKey(const Key('try-on-button')), findsOneWidget);
      expect(find.byKey(const Key('try-on-approx')), findsOneWidget);
      expect(find.text('Приблизительная передача оттенка'), findsWidgets);
    });

    testWidgets('a mascara shows nothing about palettes or colours', (t) async {
      await boot(t);
      await open(t, AppRoutes.product, idOf('Super Slim Waterproof Mascara'));
      expect(find.byKey(const Key('palette-section')), findsNothing);
      expect(find.byKey(const Key('try-on-approx')), findsNothing);
    });
  });

  group('translations of the new texts', () {
    test(
      'English and Kazakh have the same lines, with the same placeholders',
      () {
        expect(catalogKk.keys.toSet(), catalogEn.keys.toSet());
        final ph = RegExp(r'\{\w+\}');
        for (final k in catalogEn.keys) {
          final want = ph.allMatches(k).map((m) => m.group(0)).toSet();
          expect(
            ph.allMatches(catalogEn[k]!).map((m) => m.group(0)).toSet(),
            want,
          );
          expect(
            ph.allMatches(catalogKk[k]!).map((m) => m.group(0)).toSet(),
            want,
          );
        }
      },
    );

    test('tr finds them', () {
      currentLang = AppLang.en;
      expect(tr('О данных'), 'About the data');
      expect(
        trf('Цвета внутри палетки: {n}', {'n': 10}),
        'Colours inside the palette: 10',
      );
      currentLang = AppLang.kk;
      expect(
        tr('Приблизительная передача оттенка'),
        isNot(contains('Приблиз')),
      );
      currentLang = AppLang.ru;
    });
  });
}
