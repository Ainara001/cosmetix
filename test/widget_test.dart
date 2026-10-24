import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/app.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/database/seed_data.dart';

/// SQLite runs in a real isolate, so wait in real time until [finder] appears.
Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('login with the demo account opens the home screen', (
    tester,
  ) async {
    final helper = DatabaseHelper(path: inMemoryDatabasePath);
    addTearDown(() => tester.runAsync(helper.close));

    await tester.pumpWidget(CosmetixApp(helper: helper));
    await pumpUntil(tester, find.text('Добро пожаловать'));

    // empty form -> validation errors, no crash
    await tester.tap(find.text('Войти'));
    await tester.pump();
    expect(find.text('Введите email'), findsOneWidget);

    // wrong password -> inline error
    await tester.enterText(
      find.byType(TextFormField).at(0),
      SeedData.demoEmail,
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'wrong-password');
    await tester.tap(find.text('Войти'));
    await pumpUntil(tester, find.text('Неверный email или пароль'));

    // correct password -> main screen with the bottom navigation
    await tester.enterText(
      find.byType(TextFormField).at(1),
      SeedData.demoPassword,
    );
    await tester.tap(find.text('Войти'));
    await pumpUntil(tester, find.text('Кабинет'));

    expect(find.text('Главная'), findsWidgets);
    expect(find.text('Корзина'), findsWidgets);
    expect(find.text('ИИ Чат'), findsWidgets);

    // regression: "Фильтры" used to crash on a route type cast and do nothing
    // the quick-access tiles push the catalog link below the fold
    await tester.scrollUntilVisible(
      find.text('Весь каталог'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Весь каталог'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Весь каталог'));
    await pumpUntil(tester, find.text('Фильтры'));
    await tester.tap(find.text('Фильтры'));
    await pumpUntil(tester, find.text('Категория')); // filters screen opened
    await tester.scrollUntilVisible(
      find.text('Применить'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Применить'));
    await pumpUntil(tester, find.text('Фильтры'));
    expect(tester.takeException(), isNull);

    // regression: a cold start with a saved session used to leave an
    // "unavailable screen" ('/') under the main screen
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(CosmetixApp(helper: helper));
    await pumpUntil(tester, find.text('Кабинет'));
    expect(
      tester.state<NavigatorState>(find.byType(Navigator).first).canPop(),
      isFalse,
    );
    expect(find.text('Экран недоступен'), findsNothing);

    // let the background SQLite loads finish before the test ends
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  });
}
