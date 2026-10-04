import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/providers/settings_provider.dart';

import 'package:cosmetix/app.dart';
import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/i18n/translations_en.dart';
import 'package:cosmetix/core/i18n/translations_kk.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/database/seed_data.dart';
import 'package:cosmetix/models/product_filter.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/routes/route_args.dart';
import 'package:cosmetix/core/beauty/beauty_codes.dart';
import 'package:cosmetix/models/beauty_profile.dart';
import 'package:cosmetix/services/color_test_service.dart';
import 'widget_test.dart' show pumpUntil;

final _cyr = RegExp('[А-Яа-яЁё]');

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Every visible string on the current screen.
Set<String> _texts(WidgetTester t) => {
  for (final w in t.widgetList<RichText>(find.byType(RichText)))
    w.text.toPlainText(),
  for (final w in t.widgetList<EditableText>(find.byType(EditableText)))
    if (w.controller.text.isNotEmpty) w.controller.text,
};

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('tr translates, falls back to Russian, fills placeholders', () {
    currentLang = AppLang.en;
    expect(tr('Корзина'), 'Cart');
    expect(tr('нет такого ключа'), 'нет такого ключа');
    expect(trf('{n} мин назад', {'n': 5}), '5 min ago');
    currentLang = AppLang.kk;
    expect(tr('Корзина'), 'Себет');
    currentLang = AppLang.ru;
    expect(tr('Корзина'), 'Корзина');
  });

  testWidgets('switching the language rebuilds the open screens', (t) async {
    final helper = DatabaseHelper(path: inMemoryDatabasePath);
    addTearDown(() => t.runAsync(helper.close));
    addTearDown(() => currentLang = AppLang.ru);
    await t.pumpWidget(CosmetixApp(helper: helper));
    await pumpUntil(t, find.text('Добро пожаловать'));
    final settings = Provider.of<SettingsProvider>(
      t.element(find.byType(Scaffold).first),
      listen: false,
    );
    unawaited(settings.setLanguage(AppLang.en));
    await _settle(t);
    expect(find.text('Welcome'), findsOneWidget);
    expect(find.text('Добро пожаловать'), findsNothing);
  });

  for (final lang in [AppLang.en, AppLang.kk]) {
    testWidgets('no Russian left on screens in ${lang.code}', (t) async {
      t.view.physicalSize = const Size(1080, 2200);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final helper = DatabaseHelper(path: inMemoryDatabasePath);
      addTearDown(() => t.runAsync(helper.close));
      await t.pumpWidget(CosmetixApp(helper: helper));
      await pumpUntil(t, find.text('Добро пожаловать'));
      currentLang = lang;
      addTearDown(() => currentLang = AppLang.ru);
      await t.runAsync(() async {});
      await t.pump();
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
      await _settle(t);

      final offenders = <String, Set<String>>{};
      // user data (name, city) legitimately stays as typed
      const userData = {'Айнара', 'Рустемкызы', 'Астана', 'Рустемкызы Айнара'};
      final dict = lang == AppLang.en ? translationsEn : translationsKk;
      bool untranslated(String s) {
        if (userData.contains(s) || s == 'Русский') return false;
        // English must not contain Cyrillic at all; Kazakh is Cyrillic too, so
        // there we look for text that is still a Russian source string.
        if (lang == AppLang.en) return _cyr.hasMatch(s);
        return dict[s] != null && dict[s] != s;
      }

      void check(String screen) {
        for (final s in _texts(t)) {
          if (untranslated(s)) offenders.putIfAbsent(screen, () => {}).add(s);
        }
      }

      check('home');
      final ctx = t.element(find.byType(Scaffold).first);
      Future<void> visit(String name, String route, [Object? args]) async {
        Navigator.of(ctx).pushNamed(route, arguments: args);
        await _settle(t);
        check(name);
        t.state<NavigatorState>(find.byType(Navigator).last).pop();
        await _settle(t);
      }

      await visit('catalog', AppRoutes.catalog);
      await visit('search', AppRoutes.search);
      await visit(
        'filters',
        AppRoutes.filters,
        const FiltersArgs(initial: ProductFilter(), products: []),
      );
      for (final id in [1, 5]) {
        await visit('product$id', AppRoutes.product, id);
        await visit('compare$id', AppRoutes.priceCompare, id);
        await visit('reviews$id', AppRoutes.reviews, id);
        await visit('analysis$id', AppRoutes.analysis, id);
      }
      const color = ColorTestResult(
        colorType: 'Лето',
        undertone: 'Холодный',
        skinTone: 'Светлый',
      );
      await visit(
        'undertoneTest',
        AppRoutes.undertoneTest,
        const UndertoneArgs(warm: 0, depth: 0),
      );
      await visit(
        'skinTest',
        AppRoutes.skinTest,
        const SkinTestArgs(color: color),
      );
      await visit(
        'beautyPhoto',
        AppRoutes.beautyPhoto,
        const BeautyPhotoArgs(
          color: color,
          skinType: SkinType.dry,
          concerns: {SkinConcern.dryness},
        ),
      );
      await visit(
        'colorResult',
        AppRoutes.colorResult,
        BeautyResultArgs(
          profile: BeautyProfile.fromLabels(
            skinType: 'Сухая',
            skinTone: 'Светлый',
            undertone: 'Холодный',
            colorType: 'Лето',
            concerns: const ['Сухость и шелушение'],
          ),
        ),
      );
      for (final r in [
        AppRoutes.favorites,
        AppRoutes.orders,
        AppRoutes.beautyProfile,
        AppRoutes.colorTest,
        AppRoutes.editProfile,
        AppRoutes.settings,
        AppRoutes.blacklist,
        AppRoutes.reactions,
        AppRoutes.reactionForm,
        AppRoutes.legal,
      ]) {
        await visit(r, r);
      }
      for (final tab in [Icons.shopping_cart_outlined, Icons.person_outline]) {
        final f = find.byIcon(tab);
        if (f.evaluate().isNotEmpty) {
          await t.tap(f.last);
          await _settle(t);
          check('tab ${tab.codePoint}');
        }
      }
      // ignore: avoid_print
      offenders.forEach((k, v) => print('[${lang.code}] $k: $v'));
      expect(offenders, isEmpty);
    });
  }
}
