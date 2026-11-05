import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/app.dart';
import 'package:cosmetix/core/beauty/beauty_codes.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/models/beauty_profile.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/models/product_filter.dart';
import 'package:cosmetix/repositories/user_repository.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/routes/route_args.dart';
import 'package:cosmetix/screens/beauty/color_result_screen.dart';
import 'package:cosmetix/services/color_test_service.dart';
import 'widget_test.dart' show pumpUntil;

Product _p(int id, int price, int created) => Product(
  id: id,
  brand: 'B',
  name: 'P$id',
  category: 'Уход за лицом',
  zone: '',
  price: price,
  inStock: true,
  art: 'bottle',
  color: 0,
  description: '',
  naturalPercent: 80,
  createdAt: created,
);

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('sorting (pure)', () {
    final items = [_p(1, 300, 10), _p(2, 100, 30), _p(3, 200, 20)];
    List<int> ids(ProductSort s) => [
      for (final p in ProductFilter.apply(items, const ProductFilter(), s))
        p.id,
    ];

    test('newest first', () => expect(ids(ProductSort.newest), [2, 3, 1]));
    test(
      'price low to high',
      () => expect(ids(ProductSort.priceAsc), [2, 3, 1]),
    );
    test(
      'price high to low',
      () => expect(ids(ProductSort.priceDesc), [1, 3, 2]),
    );

    test('"For you" exists only with a Beauty Profile', () {
      expect(
        ProductSort.catalogOptions(hasProfile: false),
        isNot(contains(ProductSort.forYou)),
      );
      expect(
        ProductSort.catalogOptions(hasProfile: true).first,
        ProductSort.forYou,
      );
      expect(ProductSort.catalogOptions(hasProfile: true), [
        ProductSort.forYou,
        ProductSort.newest,
        ProductSort.priceAsc,
        ProductSort.priceDesc,
      ]);
    });
  });

  Future<(DatabaseHelper, int)> newUser(WidgetTester t) async {
    final helper = DatabaseHelper(path: inMemoryDatabasePath);
    addTearDown(() => t.runAsync(helper.close));
    final users = UserRepository(helper);
    final id = await t.runAsync(() async {
      final u = await users.register(
        firstName: 'Новая',
        email: 'new@test.kz',
        password: 'Passw0rd1',
      );
      await users.setCurrentUser(u.id);
      return u.id;
    });
    return (helper, id!);
  }

  NavigatorState nav(WidgetTester t) =>
      t.state<NavigatorState>(find.byType(Navigator).first);

  testWidgets('before the Beauty Test the catalog is sorted by newest', (
    t,
  ) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final (helper, _) = await newUser(t);
    await t.pumpWidget(CosmetixApp(helper: helper));
    await pumpUntil(t, find.text('Кабинет'));
    // no Beauty Profile yet: no personal block on the home screen
    expect(find.text('Рекомендуем вам'), findsNothing);
    nav(t).pushNamed(AppRoutes.catalog);
    await _settle(t);
    expect(find.text('По новизне'), findsOneWidget);
    expect(find.text('Для вас'), findsNothing);
    await t.tap(find.byTooltip('Сортировка'));
    await _settle(t);
    expect(find.text('Для вас'), findsNothing); // not offered yet
    expect(find.text('Сначала дешёвые'), findsOneWidget);
    expect(find.text('Сначала дорогие'), findsOneWidget);
  });

  testWidgets('the result screen shows no confidence percent of the AI', (
    t,
  ) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final (helper, _) = await newUser(t);
    await t.pumpWidget(CosmetixApp(helper: helper));
    await pumpUntil(t, find.text('Кабинет'));
    nav(t).pushNamed(
      AppRoutes.colorResult,
      arguments: BeautyResultArgs(
        profile: BeautyProfile.fromLabels(
          skinType: 'Сухая',
          skinTone: 'Светлый',
          undertone: 'Холодный',
          colorType: 'Лето',
          concerns: const ['Сухость и шелушение'],
          source: 'questionnaire_photo',
          confidence: 0.82, // an old saved profile may still carry the number
        ),
        photoUsed: true,
      ),
    );
    await _settle(t);
    expect(find.text('Бьюти-профиль'), findsWidgets);
    expect(find.text('Опросник + анализ фото'), findsOneWidget);
    // the model's own number is not shown: no percent, no word about confidence
    expect(find.textContaining('Уверенность'), findsNothing);
    expect(find.textContaining('82%'), findsNothing);
    expect(find.textContaining('82 %'), findsNothing);
  });

  testWidgets('finishing the Beauty Test (photo skipped) turns "For you" on', (
    t,
  ) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final (helper, userId) = await newUser(t);
    await t.pumpWidget(CosmetixApp(helper: helper));
    await pumpUntil(t, find.text('Кабинет'));

    // optional photo step: the test finishes with "Skip" and no AI at all
    nav(t).pushNamed(
      AppRoutes.beautyPhoto,
      arguments: const BeautyPhotoArgs(
        color: ColorTestResult(
          colorType: 'Лето',
          undertone: 'Холодный',
          skinTone: 'Светлый',
        ),
        skinType: SkinType.dry,
        concerns: {SkinConcern.dryness},
      ),
    );
    await _settle(t);
    expect(find.text('Фото (по желанию)'), findsOneWidget);
    await t.scrollUntilVisible(
      find.text('Пропустить'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('Пропустить'));
    await _settle(t);

    // the final Beauty Profile is shown, determined by the questionnaire only
    expect(find.text('Бьюти-профиль'), findsWidgets);
    expect(find.text('Опросник'), findsOneWidget);
    await t.scrollUntilVisible(
      find.text('Подобрать косметику для меня'),
      200,
      scrollable: find.descendant(
        of: find.byType(ColorResultScreen),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Подобрать косметику для меня'), findsOneWidget);

    final user = await t.runAsync(() => UserRepository(helper).getById(userId));
    expect(user!.colorType, 'Лето');
    expect(user.skinType, 'Сухая');
    expect(user.skinConcerns, ['Сухость и шелушение']);
    expect(user.beautySource, 'questionnaire');
    expect(user.beautyConfidence, isNull);
    expect(user.hasBeautyProfile, isTrue);

    // and the catalog now defaults to "For you"
    nav(t).pushNamed(AppRoutes.catalog);
    await _settle(t);
    expect(find.text('Для вас'), findsOneWidget);
    expect(find.text('По новизне'), findsNothing);
    // the personal list shows match labels
    expect(find.textContaining('совпадение'), findsWidgets);
  });

  testWidgets(
    'with a profile: For you hides blacklisted products; a manual sort wins',
    (t) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final helper = DatabaseHelper(path: inMemoryDatabasePath);
      addTearDown(() => t.runAsync(helper.close));
      // demo user: color type + parabens on the blacklist; CeraVe Moisturizing
      // Cream (seed product 14) contains parabens
      await t.runAsync(() => UserRepository(helper).setCurrentUser(1));
      await t.pumpWidget(CosmetixApp(helper: helper));
      await pumpUntil(t, find.text('Кабинет'));
      nav(t).pushNamed(AppRoutes.catalog);
      await _settle(t);

      expect(find.text('Для вас'), findsOneWidget);
      await t.enterText(find.byType(TextField).first, 'Moisturizing');
      await _settle(t);
      expect(find.text('Moisturizing Cream'), findsNothing);

      // the user picks "Newest": respected, and the product appears
      await t.tap(find.byTooltip('Сортировка'));
      await _settle(t);
      await t.tap(find.text('По новизне').last);
      await _settle(t);
      expect(find.text('Для вас'), findsNothing);
      expect(find.text('По новизне'), findsOneWidget);
      expect(find.text('Moisturizing Cream'), findsOneWidget);

      // still respected after other state changes (typing a search query)
      await t.enterText(find.byType(TextField).first, 'тинт');
      await _settle(t);
      expect(find.text('По новизне'), findsOneWidget);
      expect(find.text('Для вас'), findsNothing);
    },
  );
}
