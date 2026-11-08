import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cosmetix/core/beauty/beauty_codes.dart';
import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/theme/app_theme.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/screens/care/care_selection_screen.dart';

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
}
