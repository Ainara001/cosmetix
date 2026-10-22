// End-to-end scenarios of Cosmetix.
//
// Run on a booted iPhone simulator (this is the intended target):
//   flutter test integration_test -d <SIMULATOR_ID>
// They also run on the host (no device) with:
//   flutter test integration_test
//
// The AI is a local fake proxy (no network, no key, no cost). Text recognition
// and the photo picker are fakes: the real gallery picker and the real Apple
// Vision OCR are system UI and are checked by hand in the simulator.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/app.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/database/seed_data.dart';
import 'package:cosmetix/providers/ai_provider.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/services/ingredient_scan/ingredient_ocr.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/product_card.dart';
import '../test/ai_test.dart' show FakeAiProxy;

class _FakeOcr implements IngredientOcr {
  @override
  Future<String> recognize(String imagePath) async =>
      'INGREDIENTS: Aqua, Glycerin, Sodium Laureth Sulfate, Methylparaben, Parfum.';
}

class _FakePhotos implements ScanPhotoSource {
  @override
  Future<String?> pick({required bool camera}) async => 'label.png';
}

Future<void> _settle(WidgetTester t, [int rounds = 6]) async {
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
  // ignore: avoid_print
  print(
    'VISIBLE: ${[for (final w in t.widgetList<Text>(find.byType(Text))) w.data].whereType<String>().take(40).toList()}',
  );
  fail('Timed out waiting for $f');
}

/// Scrolls the first list (down, then up) until [f] is built and on screen.
Future<void> _see(WidgetTester t, Finder f) async {
  if (f.hitTestable().evaluate().isNotEmpty) return;
  final list = find.byType(Scrollable).first;
  try {
    await t.scrollUntilVisible(f, 250, scrollable: list);
  } on StateError {
    await t.scrollUntilVisible(f, -250, scrollable: list);
  }
}

Future<void> _tap(WidgetTester t, Finder f) async {
  await _see(t, f);
  await t.ensureVisible(f);
  await t.tap(f);
  await _settle(t, 3);
}

Future<void> main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isIOS && !Platform.isAndroid) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  late Directory dir;
  late String dbPath;
  late FakeAiProxy ai;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('cosmetix_it');
    dbPath = '${dir.path}/cosmetix_it.db';
    ai = await FakeAiProxy.start();
  });
  tearDown(() async {
    await ai.stop();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<DatabaseHelper> launch(
    WidgetTester t, {
    DatabaseHelper? helper,
  }) async {
    final h = helper ?? DatabaseHelper(path: dbPath);
    await t.pumpWidget(
      CosmetixApp(helper: h, ocr: _FakeOcr(), photoSource: _FakePhotos()),
    );
    return h;
  }

  Future<void> loginDemo(WidgetTester t) async {
    await _until(t, find.text('Добро пожаловать'));
    await t.enterText(find.byType(TextFormField).at(0), SeedData.demoEmail);
    await t.enterText(find.byType(TextFormField).at(1), SeedData.demoPassword);
    await t.tap(find.text('Войти'));
    await _until(t, find.text('Кабинет'));
    await _settle(t);
  }

  NavigatorState nav(WidgetTester t) =>
      t.state<NavigatorState>(find.byType(Navigator).first);

  Future<void> open(WidgetTester t, String route, [Object? args]) async {
    nav(t).pushNamed(route, arguments: args);
    await _settle(t);
  }

  testWidgets('1. first launch shows the sign-in screen', (t) async {
    await launch(t);
    await _until(t, find.text('Добро пожаловать'));
    expect(find.text('Войти'), findsWidgets);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(t.takeException(), isNull);
  });

  testWidgets('2. registration, then sign-in with the new account', (t) async {
    await launch(t);
    await _until(t, find.text('Добро пожаловать'));
    await _tap(t, find.text('Регистрация'));
    await _until(t, find.text('Зарегистрироваться'));
    final fields = find.byType(TextFormField);
    await t.enterText(fields.at(0), 'Тест');
    await t.enterText(fields.at(1), 'new.user@test.kz');
    await t.enterText(fields.at(2), 'Passw0rd1');
    await _tap(t, find.byType(Checkbox).first);
    await _tap(t, find.text('Зарегистрироваться'));
    await _until(t, find.text('Кабинет'));
    expect(t.takeException(), isNull);
  });

  testWidgets('3. moving between the main tabs', (t) async {
    await launch(t);
    await loginDemo(t);
    for (final tab in ['Корзина', 'ИИ Чат', 'Кабинет', 'Главная']) {
      await _tap(t, find.text(tab).last);
    }
    await _see(t, find.text('Весь каталог'));
    // the quick-access tiles lead to the personal tools and back
    await _tap(t, find.text('Косметичка'));
    expect(find.text('Моя косметичка'), findsWidgets);
    nav(t).pop();
    await _settle(t);
    expect(t.takeException(), isNull);
  });

  testWidgets('4. catalog and a product card', (t) async {
    await launch(t);
    await loginDemo(t);
    await open(t, AppRoutes.catalog);
    await _until(t, find.byType(ProductCard));
    await t.tap(find.byType(ProductCard).first);
    await _until(t, find.text('О товаре'));
    expect(find.text('В корзину'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('5. search and filters', (t) async {
    await launch(t);
    await loginDemo(t);
    await open(t, AppRoutes.search);
    await t.enterText(find.byType(TextField).first, 'Flower');
    await t.testTextInput.receiveAction(TextInputAction.search);
    await _settle(t, 8);
    expect(find.textContaining('Flower'), findsWidgets);
    nav(t).pop();
    await _settle(t);
    await open(t, AppRoutes.catalog);
    await _tap(t, find.text('Фильтры'));
    await _until(t, find.text('Категория'));
    await _tap(t, find.text('Применить'));
    expect(t.takeException(), isNull);
  });

  testWidgets('6. favorites and cart', (t) async {
    await launch(t);
    await loginDemo(t);
    // product 8 is in stock and not yet a favorite of the demo user
    await open(t, AppRoutes.product, 8);
    await _until(t, find.text('О товаре'));
    await _tap(t, find.byTooltip('В избранное'));
    expect(find.byTooltip('Убрать из избранного'), findsOneWidget);
    // the confirmation snack bar covers the bottom button: wait until it is gone
    await _settle(t, 45);
    await _tap(t, find.text('В корзину').first);
    nav(t).pop();
    await _settle(t);
    await _tap(t, find.text('Корзина').last);
    expect(find.text('Оформить заказ'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('7-8. skin type and color type tests give a Beauty profile', (
    t,
  ) async {
    await launch(t);
    await loginDemo(t);
    await open(t, AppRoutes.colorTest);
    // 5 questions: the first option every time
    for (var step = 0; step < 5; step++) {
      await t.tap(find.byType(AppCard).first);
      await _settle(t, 2);
      await _tap(t, find.text(step == 4 ? 'К тесту на подтон' : 'Далее'));
    }
    // undertone test
    await _until(t, find.text('Тест на подтон кожи'));
    await t.tap(find.byIcon(Icons.radio_button_unchecked).first);
    await _tap(t, find.text('Завершить и показать результат'));
    // skin test: the first skin type, then Next
    await _until(t, find.text('Тест: ваша кожа'));
    await t.tap(find.byIcon(Icons.radio_button_off).first);
    await _tap(t, find.text('Далее'));
    // optional photo step is skipped
    await _until(t, find.text('Пропустить'));
    await _tap(t, find.text('Пропустить'));
    await _until(t, find.text('Подобрать косметику для меня'));
    expect(t.takeException(), isNull);
  });

  testWidgets('9. a custom component goes on the blacklist', (t) async {
    await launch(t);
    await loginDemo(t);
    await open(t, AppRoutes.blacklist);
    await t.enterText(
      find.widgetWithText(TextField, 'Добавить свой компонент...').first,
      'Лимонен',
    );
    await _tap(t, find.byTooltip('Добавить'));
    expect(find.text('Лимонен'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('10. an ingredient photo is read and checked (fake OCR)', (
    t,
  ) async {
    await launch(t);
    await loginDemo(t);
    await open(t, AppRoutes.scan);
    await _tap(t, find.text('Выбрать фото из галереи'));
    expect(find.textContaining('Состав распознан'), findsOneWidget);
    await _tap(t, find.text('Проверить по чёрному списку'));
    await _see(t, find.textContaining('Найдено совпадений'));
    expect(find.textContaining('Парабены'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('11-12. a product in the cosmetic bag and a morning plan', (
    t,
  ) async {
    await launch(t);
    await loginDemo(t);
    await open(t, AppRoutes.bag);
    await _tap(t, find.text('Добавить средство'));
    await t.enterText(find.byType(TextFormField).at(0), 'Крем для лица');
    await _tap(t, find.text('Добавить в косметичку'));
    await _until(t, find.text('Крем для лица'));
    await open(t, AppRoutes.care);
    await _tap(t, find.text('Утро'));
    await _tap(t, find.text('Добавить средство в план'));
    await _tap(t, find.text('Крем для лица').last);
    expect(find.textContaining('1. Крем для лица'), findsOneWidget);
    await t.tap(find.byType(Checkbox).first);
    await _settle(t, 3);
    expect(find.text('Сегодня отмечено: 1 из 1'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('13. a reaction record in the diary', (t) async {
    await launch(t);
    await loginDemo(t);
    await open(t, AppRoutes.reactions);
    await _tap(t, find.text('Добавить реакцию'));
    await _until(t, find.text('Добавить в дневник'));
    final drop = find.byType(DropdownButtonFormField<int>);
    await _tap(t, drop);
    await _tap(t, find.byType(DropdownMenuItem<int>).first);
    final type = find.byType(DropdownButtonFormField<String>);
    await _tap(t, type);
    await _tap(t, find.byType(DropdownMenuItem<String>).first);
    await _tap(t, find.text('Добавить в дневник'));
    await _until(t, find.text('История кожных реакций'));
    expect(t.takeException(), isNull);
  });

  testWidgets('14. a question to the AI consultant (fake proxy)', (t) async {
    ai.chatAnswer = 'Это крем подойдёт для сухой кожи.';
    await launch(t);
    await loginDemo(t);
    final ctx = t.element(find.byType(Scaffold).first);
    await t.runAsync(() async {
      final provider = ctx.read<AiProvider>();
      await provider.update(baseUrl: ai.url);
      await provider.setShareProfile(true); // consent was given
    });
    await _tap(t, find.text('ИИ Чат').last);
    await t.enterText(find.byType(TextField).last, 'Какой крем выбрать?');
    await _tap(t, find.byTooltip('Отправить'));
    await _until(t, find.text('Это крем подойдёт для сухой кожи.'));
    expect(ai.requests.single['system'], contains('USER BEAUTY PROFILE'));
    expect(t.takeException(), isNull);
  });

  testWidgets('15. the AI being unavailable is handled', (t) async {
    await launch(t);
    await loginDemo(t);
    final ctx = t.element(find.byType(Scaffold).first);
    await t.runAsync(() async {
      final provider = ctx.read<AiProvider>();
      await provider.update(baseUrl: 'http://127.0.0.1:1');
      await provider.setShareProfile(false);
    });
    await _tap(t, find.text('ИИ Чат').last);
    await t.enterText(find.byType(TextField).last, 'Привет');
    await _tap(t, find.byTooltip('Отправить'));
    await _until(t, find.text('ИИ-помощник сейчас недоступен'));
    expect(find.text('Повторить'), findsOneWidget);
    // the rest of the app still works
    await _tap(t, find.text('Корзина').last);
    expect(t.takeException(), isNull);
  });

  testWidgets('16. data survives a full restart', (t) async {
    var helper = await launch(t);
    await loginDemo(t);
    await open(t, AppRoutes.bag);
    await _tap(t, find.text('Добавить средство'));
    await t.enterText(find.byType(TextFormField).at(0), 'Сыворотка Тест');
    await _tap(t, find.text('Добавить в косметичку'));
    await _until(t, find.text('Сыворотка Тест'));

    // close everything and start again from the same database file
    await t.pumpWidget(const SizedBox());
    await t.runAsync(helper.close);
    helper = await launch(t, helper: DatabaseHelper(path: dbPath));
    // the saved session opens the main screen straight away
    await _until(t, find.text('Кабинет'));
    await open(t, AppRoutes.bag);
    await _until(t, find.text('Сыворотка Тест'));
    await t.runAsync(helper.close);
    expect(t.takeException(), isNull);
  });
}
