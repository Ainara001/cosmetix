import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/app.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/database/seed_data.dart';
import 'package:cosmetix/providers/auth_provider.dart';
import 'package:cosmetix/providers/cart_provider.dart';
import 'package:cosmetix/repositories/cart_repository.dart';
import 'package:cosmetix/repositories/user_repository.dart';
import 'widget_test.dart' show pumpUntil;

/// A price text such as "3 700 тг" (the group separator is not a plain space).
Finder _price(String digits) => find.byWidgetPredicate(
  (w) =>
      w is Text && (w.data ?? '').replaceAll(RegExp(r'\s'), '') == '$digitsтг',
);

Future<void> _settle(WidgetTester t, [int rounds = 6]) async {
  for (var i = 0; i < rounds; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('forgot password: the code from the dialog resets the password', (
    t,
  ) async {
    t.view.physicalSize = const Size(1080, 2200);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final helper = DatabaseHelper(path: inMemoryDatabasePath);
    addTearDown(() => t.runAsync(helper.close));
    await t.pumpWidget(CosmetixApp(helper: helper));
    await pumpUntil(t, find.text('Добро пожаловать'));

    await t.tap(find.text('Забыли пароль?'));
    await _settle(t);
    await t.enterText(find.byType(TextFormField), SeedData.demoEmail);
    await t.tap(find.text('Отправить код'));
    await pumpUntil(t, find.text('Код отправлен'));

    final message = t
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data ?? '')
        .firstWhere((s) => s.contains('Ваш код:'));
    final code = RegExp(r'Ваш код: (\d{6})').firstMatch(message)!.group(1)!;
    await t.tap(find.text('Понятно'));
    await _settle(t);

    // reset screen: a wrong code is rejected and nothing changes
    await t.enterText(find.byType(TextFormField).at(0), '000000');
    await t.enterText(find.byType(TextFormField).at(1), 'BrandNew123');
    await t.enterText(find.byType(TextFormField).at(2), 'BrandNew123');
    await t.tap(find.text('Сохранить пароль'));
    await pumpUntil(t, find.text('Неверный код'));
    final users = UserRepository(helper);
    await t.runAsync(() async {
      expect(await users.login(SeedData.demoEmail, 'BrandNew123'), isNull);
    });

    // the right code changes the password
    await t.enterText(find.byType(TextFormField).at(0), code);
    await t.tap(find.text('Сохранить пароль'));
    await pumpUntil(t, find.text('Добро пожаловать'));
    await t.runAsync(() async {
      expect(await users.login(SeedData.demoEmail, 'BrandNew123'), isNotNull);
      expect(
        await users.login(SeedData.demoEmail, SeedData.demoPassword),
        isNull,
      );
    });
    expect(t.takeException(), isNull);
    await _settle(t);
  });

  testWidgets('cart: spending bonus points lowers the total and is shown', (
    t,
  ) async {
    t.view.physicalSize = const Size(1080, 2200);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final helper = DatabaseHelper(path: inMemoryDatabasePath);
    addTearDown(() => t.runAsync(helper.close));
    await t.pumpWidget(CosmetixApp(helper: helper));
    await pumpUntil(t, find.text('Добро пожаловать'));
    await t.enterText(find.byType(TextFormField).at(0), SeedData.demoEmail);
    await t.enterText(find.byType(TextFormField).at(1), SeedData.demoPassword);
    await t.tap(find.text('Войти'));
    await pumpUntil(t, find.text('Кабинет'));
    await _settle(t);

    final ctx = t.element(find.byType(Scaffold).first);
    await t.runAsync(() async {
      await UserRepository(helper).addBonus(1, 500);
      await CartRepository(helper).add(1, 1, 1); // 3 700 тг
    });
    await t.runAsync(() => ctx.read<CartProvider>().load(1));
    await t.runAsync(() => ctx.read<AuthProvider>().reload());
    await t.tap(find.text('Корзина').last);
    await _settle(t);

    expect(find.text('Списать бонусы: −500'), findsOneWidget);
    expect(_price('3700'), findsWidgets);
    await t.tap(find.byType(Switch));
    await _settle(t, 2);
    expect(_price('3200'), findsWidgets);

    await t.tap(find.text('Оформить заказ'));
    await _settle(t, 2);
    expect(find.textContaining('Списано бонусов: −500'), findsOneWidget);
    await t.tap(find.text('Оформить'));
    await pumpUntil(t, find.text('Списано бонусов'));
    expect(find.text('−500'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.runAsync(() async {
      // 500 owned - 500 spent + 2% of 3 200
      expect((await UserRepository(helper).getById(1))!.bonusPoints, 64);
    });
    await _settle(t);
  });
}
