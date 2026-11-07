// Screenshots of the main product screens for the before/after comparison of
// a design change. The same scenario runs on the old and on the new design.
//
//   flutter test integration_test/design_shots_test.dart -d <SIMULATOR_ID> \
//     --dart-define=SHOT_DIR=/absolute/path/to/docs/ui-redesign/before
//
// It uses its own temporary database (the demo catalog), so the data of the
// app on the device is not read; reinstalling the app for the run does reset
// the app's own data on the simulator.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/app.dart';
import 'package:cosmetix/database/catalog_data.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/database/seed_data.dart';
import 'package:cosmetix/providers/settings_provider.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/routes/route_args.dart';

const _shotDir = String.fromEnvironment('SHOT_DIR');

Future<void> _settle(WidgetTester t, [int rounds = 8]) async {
  for (var i = 0; i < rounds; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _until(WidgetTester t, Finder f, {int tries = 120}) async {
  for (var i = 0; i < tries; i++) {
    await _settle(t, 1);
    if (f.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $f');
}

Future<void> main() async {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isIOS && !Platform.isAndroid) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  testWidgets('screens of the catalog, a palette and the try-on', (t) async {
    if (_shotDir.isEmpty) {
      markTestSkipped('SHOT_DIR is not set');
      return;
    }
    Directory(_shotDir).createSync(recursive: true);
    final dir = Directory.systemTemp.createTempSync('cosmetix_shots');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<void> shot(String name) async {
      await _settle(t, 6);
      final bytes = await binding.takeScreenshot(name);
      File('$_shotDir/$name.png').writeAsBytesSync(bytes);
    }

    final catalog = await CatalogData.load();
    int idOf(String name) =>
        catalog.products.indexWhere((p) => p.name == name) + 1;

    final helper = DatabaseHelper(path: '${dir.path}/shots.db');
    await t.pumpWidget(CosmetixApp(helper: helper));
    await _until(t, find.text('Добро пожаловать'));
    await t.enterText(find.byType(TextFormField).at(0), SeedData.demoEmail);
    await t.enterText(find.byType(TextFormField).at(1), SeedData.demoPassword);
    // on a small phone the button is below the fold of the login form
    await t.ensureVisible(find.text('Войти'));
    await _settle(t, 2);
    await t.tap(find.text('Войти'));
    await _until(t, find.text('Кабинет'));
    await _settle(t);

    NavigatorState nav() =>
        t.state<NavigatorState>(find.byType(Navigator).first);
    Future<void> open(String route, [Object? args]) async {
      nav().pushNamed(route, arguments: args);
      await _settle(t, 12);
    }

    Future<void> back() async {
      nav().pop();
      await _settle(t, 6);
    }

    Future<void> scrollDown(double px) async {
      // the vertical list of the screen (the first scrollable can be a row of chips)
      final list = find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first;
      await t.drag(list, Offset(0, -px));
      await _settle(t, 4);
    }

    await shot('01-home');

    // makeup catalog
    await open(AppRoutes.catalog, const CatalogArgs(category: 'Макияж'));
    await shot('02-catalog-makeup');
    await scrollDown(900);
    await shot('03-catalog-makeup-scrolled');
    await back();

    // a lipstick with two shades
    await open(AppRoutes.product, idOf('Ink Mood Glowy Tint 30 Happy Berry'));
    await shot('04-product-lipstick');
    await scrollDown(500);
    await shot('05-product-lipstick-lower');
    await back();

    // a palette
    await open(
      AppRoutes.product,
      idOf('Better Than Palette 02 Mahogany Garden'),
    );
    await shot('06-product-palette');
    await scrollDown(500);
    await shot('07-product-palette-lower');
    await back();

    // a product whose number of cells is not known
    await open(AppRoutes.product, idOf('Better Than Eyes'));
    await shot('08-product-eyes-unknown-cells');
    await back();

    // the try-on of a lipstick, before a photo is chosen
    await open(
      AppRoutes.virtualMakeup,
      idOf('Ink Mood Glowy Tint 30 Happy Berry'),
    );
    await shot('09-tryon-lipstick');
    await back();

    // the same palette in the dark theme
    final ctx = t.element(find.byType(Navigator).first);
    await ctx.read<SettingsProvider>().setTheme(ThemeMode.dark);
    await _settle(t, 8);
    await open(AppRoutes.catalog, const CatalogArgs(category: 'Макияж'));
    await shot('10-catalog-makeup-dark');
    await back();
    await open(
      AppRoutes.product,
      idOf('Better Than Palette 02 Mahogany Garden'),
    );
    await shot('11-product-palette-dark');
    await back();
    await ctx.read<SettingsProvider>().setTheme(ThemeMode.light);
    expect(t.takeException(), isNull);
    await helper.close();
  }, timeout: const Timeout(Duration(minutes: 10)));
}
