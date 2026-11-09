import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/core/beauty/beauty_codes.dart';
import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/theme/app_theme.dart';
import 'package:cosmetix/core/face/face_zones.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/models/skin_marks.dart';
import 'package:cosmetix/providers/auth_provider.dart';
import 'package:cosmetix/repositories/skin_marks_repository.dart';
import 'package:cosmetix/repositories/user_repository.dart';
import 'package:cosmetix/screens/care/care_selection_screen.dart';
import 'package:cosmetix/widgets/common_widgets.dart';

Product _p(int id, String inci, {int price = 5000, String name = 'Средство'}) =>
    Product(
      id: id,
      brand: 'Бренд',
      name: name,
      category: 'Уход',
      zone: 'Лицо',
      price: price,
      art: 'bottle',
      color: 0,
      description: '',
      naturalPercent: 80,
      createdAt: id,
      inci: inci,
    );

void main() {
  currentLang = AppLang.ru;

  Future<void> pump(
    WidgetTester t,
    List<Product> products, {
    double height = 3000,
  }) async {
    t.view.physicalSize = Size(1080, height);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: CareSelectionScreen(
          products: products,
          initialSkinType: SkinType.oily,
          initialConcerns: const {SkinConcern.acne},
        ),
      ),
    );
    await t.pump();
  }

  testWidgets('lists verified prices and skips no-price / irrelevant items', (
    t,
  ) async {
    await pump(t, [
      _p(
        1,
        'Water, Niacinamide, Salicylic Acid',
        price: 4500,
        name: 'Сыворотка',
      ),
      _p(2, 'Water, Butylene Glycol', price: 3000, name: 'Крем'),
      _p(3, 'Water, Tranexamic Acid', price: 0, name: 'Без цены'),
    ]);

    await t.ensureVisible(find.byType(TextField));
    await t.enterText(find.byType(TextField), '10000');
    await t.ensureVisible(find.text('Подобрать'));
    await t.tap(find.text('Подобрать'));
    await t.pump();

    expect(find.textContaining('Сыворотка'), findsOneWidget);
    expect(
      find.textContaining('Цена не подтверждена'),
      findsNothing,
    ); // has price
    expect(find.textContaining('Крем'), findsNothing); // no actives
    expect(find.textContaining('Без цены'), findsNothing); // no verified price
  });

  testWidgets('pregnancy excludes retinoid products', (t) async {
    await pump(t, [
      _p(1, 'Water, Retinol', price: 5000, name: 'Ретинол'),
      _p(2, 'Water, Niacinamide', price: 5000, name: 'Ниацинамид'),
    ]);

    await t.ensureVisible(find.text('Беременность или планирование'));
    await t.tap(find.text('Беременность или планирование'));
    await t.pump();
    await t.ensureVisible(find.text('Подобрать'));
    await t.tap(find.text('Подобрать'));
    await t.pump();

    expect(
      find.textContaining('Ниацинамид'),
      findsWidgets,
    ); // shown (name + active)
    expect(find.textContaining('Ретинол'), findsNothing);
  });

  testWidgets('nothing with a verified price: the reason is said, not hidden', (
    t,
  ) async {
    await pump(t, [
      _p(1, 'Water, Niacinamide', price: 0, name: 'А'),
      _p(2, 'Water, Salicylic Acid', price: 0, name: 'Б'),
    ]);
    await t.ensureVisible(find.text('Подобрать'));
    await t.tap(find.text('Подобрать'));
    await t.pump();
    expect(find.text('Подходящих товаров не найдено'), findsOneWidget);
    await t.scrollUntilVisible(
      find.text('Нет проверенной цены — 2'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Не вошли в подбор'), findsOneWidget);
    expect(find.text('Нет проверенной цены — 2'), findsOneWidget);
  });

  testWidgets('pregnancy: the person sees why retinol is left out', (t) async {
    await pump(t, [
      _p(1, 'Water, Retinol', price: 5000, name: 'Ретинол'),
      _p(2, 'Water, Niacinamide', price: 5000, name: 'Ниацинамид'),
    ], height: 6000); // tall: the whole list is built
    await t.ensureVisible(find.text('Беременность или планирование'));
    await t.tap(find.text('Беременность или планирование'));
    await t.pump();
    await t.ensureVisible(find.text('Подобрать'));
    await t.tap(find.text('Подобрать'));
    await t.pump();
    expect(
      find.text(
        'При беременности ретиноиды не используют: спросите врача. — 1',
      ),
      findsOneWidget,
    );
  });

  testWidgets('concerns marked on the face zones are pre-selected', (t) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    t.view.physicalSize = const Size(1080, 3000);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final helper = DatabaseHelper(path: inMemoryDatabasePath);
    addTearDown(() => t.runAsync(helper.close));
    final users = UserRepository(helper);
    final marks = SkinMarksRepository(helper);
    await t.runAsync(() async {
      final u = await users.register(
        firstName: 'Тест',
        email: 'care${DateTime.now().microsecondsSinceEpoch}@test.kz',
        password: 'Passw0rd1',
      );
      await users.setCurrentUser(u.id);
      await marks.replace(u.id, {
        const SkinZoneMark(FaceZone.chin, SkinFeature.acne),
      });
    });
    final auth = AuthProvider(users);
    await t.runAsync(auth.restoreSession);
    await t.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          Provider<SkinMarksRepository>.value(value: marks),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const CareSelectionScreen(products: []),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await t.pump();
    }
    AppChip chip(String label) =>
        t.widget<AppChip>(find.widgetWithText(AppChip, label));
    expect(chip('Акне и высыпания').selected, isTrue);
    expect(
      chip(
        tr(SkinConcern.values.firstWhere((c) => c != SkinConcern.acne).label),
      ).selected,
      isFalse,
    );
  });
}
