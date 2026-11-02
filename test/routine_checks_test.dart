import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/app.dart';
import 'package:cosmetix/core/i18n/translations_en.dart';
import 'package:cosmetix/core/i18n/translations_kk.dart';
import 'package:cosmetix/core/beauty/beauty_codes.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/database/seed_data.dart';
import 'package:cosmetix/models/care_models.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/providers/care_provider.dart';
import 'package:cosmetix/repositories/care_repository.dart';
import 'package:cosmetix/repositories/cart_repository.dart';
import 'package:cosmetix/repositories/product_repository.dart';
import 'package:cosmetix/repositories/user_repository.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/services/ingredient_catalog.dart';
import 'package:cosmetix/services/routine_checks.dart';
import 'widget_test.dart' show pumpUntil;

RoutineItem _item(
  String title, {
  Set<String> actives = const {},
  FormulaBase base = FormulaBase.unknown,
  bool foundation = false,
  bool skincare = true,
  int? id,
}) => RoutineItem(
  title: title,
  actives: actives,
  base: base,
  isFoundation: foundation,
  isSkincare: skincare,
  productId: id,
);

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

  group('active ingredient conflicts', () {
    List<IssueSeverity> sev(List<RoutineItem> i) => [
      for (final x in ActiveRules.check(i)) x.severity,
    ];

    test('retinol with an acid: do not use together', () {
      final r = ActiveRules.check([
        _item('Retinol', actives: {'retinoid'}),
        _item('Glycolic toner', actives: {'glycolic'}),
      ]);
      expect(r.single.severity, IssueSeverity.avoid);
      expect(r.single.text, contains('Retinol'));
      expect(r.single.text, contains('Glycolic toner'));
      expect(r.single.text, contains('ретиноиды и кислоты'));
    });

    test('retinol with vitamin C: separate by time of day', () {
      final r = ActiveRules.check([
        _item('Vit C', actives: {'vitamin_c'}),
        _item('Retinol', actives: {'retinoid'}),
      ]);
      expect(r.single.severity, IssueSeverity.caution);
      expect(r.single.text, contains('витамин C утром, ретинол вечером'));
    });

    test('retinoid + benzoyl peroxide: avoid; vitamin C + acid: caution', () {
      expect(
        sev([
          _item('A', actives: {'retinoid'}),
          _item('B', actives: {'benzoyl'}),
        ]),
        [IssueSeverity.avoid],
      );
      expect(
        sev([
          _item('A', actives: {'vitamin_c'}),
          _item('B', actives: {'salicylic'}),
        ]),
        [IssueSeverity.caution],
      );
    });

    test('two different acids are a caution, the same acid twice is not', () {
      expect(
        sev([
          _item('A', actives: {'glycolic'}),
          _item('B', actives: {'salicylic'}),
        ]),
        [IssueSeverity.caution],
      );
      expect(
        sev([
          _item('A', actives: {'glycolic'}),
          _item('B', actives: {'glycolic'}),
        ]),
        isEmpty,
      );
    });

    test('harmless pairs stay quiet (no invented conflicts)', () {
      expect(
        sev([
          _item('Niacinamide', actives: {'niacinamide'}),
          _item('Vit C', actives: {'vitamin_c'}),
          _item('HA', actives: {'hyaluronic'}),
          _item('Retinol', actives: {'retinoid'}),
          _item('Ceramides', actives: {'ceramide'}),
        ]).where((s) => s == IssueSeverity.avoid),
        isEmpty,
      );
      expect(
        sev([
          _item('Niacinamide', actives: {'niacinamide'}),
          _item('Vit C', actives: {'vitamin_c'}),
        ]),
        isEmpty,
      );
    });

    test('the strongest rule wins per pair; one product twice is no pair', () {
      final both = _item('Combo', actives: {'retinoid', 'vitamin_c'});
      final acid = _item('Acid', actives: {'glycolic'});
      final r = ActiveRules.check([both, acid]);
      expect(r.length, 1);
      expect(r.single.severity, IssueSeverity.avoid);
      expect(
        ActiveRules.check([
          _item('X', actives: {'retinoid'}, id: 5),
          _item('X', actives: {'glycolic'}, id: 5),
        ]),
        isEmpty,
      );
    });
  });

  group('actives from the INCI list and from a typed name', () {
    test('INCI of real products', () {
      expect(
        IngredientCatalog.detect(
          'Aqua, Retinol, Squalane, Glycolic Acid, Ascorbic Acid, Benzoyl Peroxide',
        ),
        containsAll(['retinoid', 'glycolic', 'vitamin_c', 'benzoyl']),
      );
    });

    test('typed names are understood, look-alikes are not', () {
      expect(
        IngredientCatalog.detectInText('Сыворотка с ретинолом 0.5%'),
        contains('retinoid'),
      );
      expect(
        IngredientCatalog.detectInText('Vitamin C 15% serum'),
        contains('vitamin_c'),
      );
      expect(
        IngredientCatalog.detectInText('AHA/BHA пилинг'),
        containsAll(['salicylic', 'glycolic']),
      );
      expect(
        IngredientCatalog.detectInText('Гликолевая кислота 7%'),
        contains('glycolic'),
      );
      expect(IngredientCatalog.detectInText('Пропиленгликоль крем'), isEmpty);
      expect(IngredientCatalog.detectInText('Молочное мыло'), isEmpty);
      expect(IngredientCatalog.detectInText('Крем с ha'), isEmpty);
    });

    test('a bag entry without a catalog product is read from its name', () {
      const m = MyProduct(id: 1, name: 'Сыворотка с ретинолом', brand: 'X');
      final i = RoutineItem.fromBag(m, null);
      expect(i.actives, contains('retinoid'));
      expect(i.isSkincare, isTrue);
      const f = MyProduct(id: 2, name: 'Тональный крем Y', category: 'Макияж');
      expect(RoutineItem.fromBag(f, null).isFoundation, isTrue);
      expect(RoutineItem.fromBag(f, null).isSkincare, isFalse);
    });
  });

  group('formula base', () {
    test('water, silicone and oil formulas are told apart', () {
      expect(
        FormulaAnalyzer.baseOf(
          'Aqua, Glycerin, Cetearyl Alcohol, Caprylic/Capric Triglyceride, Cetyl Alcohol',
        ),
        FormulaBase.water,
      );
      expect(
        FormulaAnalyzer.baseOf(
          'Water, Disteardimonium Hectorite, Pentylene Glycol, Cetearyl Dimethicone Crosspolymer, PEG-10 Dimethicone, Acrylates/Polytrimethylsiloxymethacrylate Copolymer',
        ),
        FormulaBase.silicone,
      );
      expect(
        FormulaAnalyzer.baseOf(
          'Water, Myristyl Alcohol, Mineral Oil, Glycerin, Butylene Glycol, Stearic Acid, Petrolatum',
        ),
        FormulaBase.oil,
      );
      expect(FormulaAnalyzer.baseOf(''), FormulaBase.unknown);
      expect(
        FormulaAnalyzer.baseOf('Snail Filtrate, Betaine'),
        FormulaBase.unknown,
      );
    });

    test(
      'the catalog: Missha cushion is silicone, Nivea oil, CeraVe water',
      () async {
        final h = DatabaseHelper(path: inMemoryDatabasePath);
        addTearDown(h.close);
        final all = await ProductRepository(h).getAll(1);
        FormulaBase baseOf(String name) => RoutineItem.fromProduct(
          all.firstWhere((p) => p.name.contains(name)),
        ).base;
        expect(baseOf('Magic Cushion'), FormulaBase.silicone);
        expect(baseOf('Soft Moisturizing'), FormulaBase.oil);
        expect(baseOf('Moisturizing Cream'), FormulaBase.water);
        expect(
          RoutineItem.fromProduct(
            all.firstWhere((p) => p.name.contains('Magic Cushion')),
          ).isFoundation,
          isTrue,
        );
      },
    );
  });

  group('foundation over care', () {
    final siliconeFd = _item(
      'Silicone FD',
      base: FormulaBase.silicone,
      foundation: true,
      skincare: false,
    );
    final waterFd = _item(
      'Water FD',
      base: FormulaBase.water,
      foundation: true,
      skincare: false,
    );
    final oilCream = _item('Oil cream', base: FormulaBase.oil);
    final siCream = _item('Si cream', base: FormulaBase.silicone);
    final waterCream = _item('Water cream', base: FormulaBase.water);

    test('silicone foundation over an oil-rich cream slides', () {
      final r = MakeupCompatibility.check(oilCream, siliconeFd)!;
      expect(r.severity, IssueSeverity.caution);
      expect(r.text, contains('скользить'));
    });

    test(
      'water foundation over a silicone cream or an oil cream is flagged',
      () {
        expect(
          MakeupCompatibility.check(siCream, waterFd)!.text,
          contains('скатываться'),
        );
        expect(
          MakeupCompatibility.check(oilCream, waterFd)!.text,
          contains('полосы'),
        );
      },
    );

    test('matching bases and unknown formulas say nothing', () {
      expect(MakeupCompatibility.check(waterCream, siliconeFd), isNull);
      expect(MakeupCompatibility.check(siCream, siliconeFd), isNull);
      expect(MakeupCompatibility.check(waterCream, waterFd), isNull);
      expect(MakeupCompatibility.check(_item('?'), siliconeFd), isNull);
      // a lipstick is not "care under a foundation"
      expect(
        MakeupCompatibility.check(
          _item('Lip', base: FormulaBase.oil, skincare: false),
          siliconeFd,
        ),
        isNull,
      );
    });

    test('in a plan only what comes BEFORE the foundation counts', () {
      final under = MakeupCompatibility.checkAll([
        oilCream,
        siliconeFd,
      ], ordered: true);
      final after = MakeupCompatibility.checkAll([
        siliconeFd,
        oilCream,
      ], ordered: true);
      expect(under.length, 1);
      expect(after, isEmpty);
      // in a bag the order is unknown: it is flagged either way
      expect(MakeupCompatibility.checkAll([siliconeFd, oilCream]).length, 1);
    });
  });

  group('patch test advice', () {
    final line = [_item('A'), _item('B'), _item('C')];

    test('a whole line at once on a sensitive skin', () {
      final r = PatchTestAdvice.forItems(line, sensitive: true);
      expect(r.length, 1);
      expect(r.single.text, contains('Сразу 3 средств'));
      expect(r.single.text, contains('3–4 дня'));
    });

    test('not for a normal skin, a short list or makeup', () {
      expect(PatchTestAdvice.forItems(line, sensitive: false), isEmpty);
      expect(
        PatchTestAdvice.forItems(line.take(2).toList(), sensitive: true),
        isEmpty,
      );
      expect(
        PatchTestAdvice.forItems([
          _item('A', skincare: false),
          _item('B', skincare: false),
          _item('C', skincare: false),
        ], sensitive: true),
        isEmpty,
      );
    });

    test('an active product on a sensitive skin gets its own advice', () {
      final r = PatchTestAdvice.forItems([
        _item('Retinol', actives: {'retinoid'}),
      ], sensitive: true);
      expect(r.single.text, contains('«Retinol»'));
      expect(
        PatchTestAdvice.forItems([
          _item('Retinol', actives: {'retinoid'}),
        ], sensitive: false),
        isEmpty,
      );
    });
  });

  group('the care provider and the screens', () {
    late DatabaseHelper helper;
    late CareProvider care;
    late CareRepository repo;

    setUp(() async {
      helper = DatabaseHelper(path: inMemoryDatabasePath);
      repo = CareRepository(helper);
      care = CareProvider(repo);
    });
    tearDown(() => helper.close());

    Future<MyProduct> add(
      String name, {
      String category = 'Уход за лицом',
    }) async {
      final id = await repo.addToBag(
        1,
        MyProduct(id: 0, name: name, category: category),
      );
      await care.load(1);
      return care.bag.firstWhere((m) => m.id == id);
    }

    test('conflicts of a plan are found per period, in order', () async {
      final retinol = await add('Сыворотка с ретинолом');
      final acid = await add('Гликолевая кислота 7%');
      final vitc = await add('Витамин C сыворотка');
      Product? none(int id) => null;

      expect(care.planIssues(CarePeriod.evening, none), isEmpty);
      await care.addStep(CarePeriod.evening, retinol);
      await care.addStep(CarePeriod.evening, acid);
      final evening = care.planIssues(CarePeriod.evening, none);
      expect(evening.single.severity, IssueSeverity.avoid);
      // the other period is a separate routine
      expect(care.planIssues(CarePeriod.morning, none), isEmpty);
      // vitamin C in the morning, retinol in the evening: exactly the advice
      await care.addStep(CarePeriod.morning, vitc);
      expect(care.planIssues(CarePeriod.morning, none), isEmpty);
      // a new step is checked before it is added
      expect(
        care
            .planIssues(
              CarePeriod.evening,
              none,
              extra: RoutineItem.fromBag(vitc, null),
            )
            .length,
        greaterThan(evening.length),
      );
    });

    test('the bag items use the catalog product when there is one', () async {
      final all = await ProductRepository(helper).getAll(1);
      final nivea = all.firstWhere((p) => p.name.contains('Soft Moisturizing'));
      final id = await repo.addToBag(
        1,
        MyProduct(
          id: 0,
          name: nivea.name,
          brand: nivea.brand,
          productId: nivea.id,
        ),
      );
      await care.load(1);
      final items = care.bagItems(
        (i) => all.where((p) => p.id == i).firstOrNull,
      );
      expect(items.single.base, FormulaBase.oil);
      expect(id, isPositive);
    });

    testWidgets(
      'the care screen warns about a conflict and says it before adding',
      (t) async {
        t.view.physicalSize = const Size(1080, 2400);
        t.view.devicePixelRatio = 3;
        addTearDown(t.view.reset);
        final h = DatabaseHelper(path: inMemoryDatabasePath);
        addTearDown(() => t.runAsync(h.close));
        await t.runAsync(() => UserRepository(h).setCurrentUser(1));
        final r = CareRepository(h);
        Future<int> bag(String n) =>
            r.addToBag(1, MyProduct(id: 0, name: n, category: 'Уход за лицом'));
        await t.runAsync(() async {
          final a = await bag('Ретинол сыворотка');
          final b = await bag('Гликолевая кислота тоник');
          await r.addStep(1, CarePeriod.evening, a);
          await r.addStep(1, CarePeriod.evening, b);
        });
        await t.pumpWidget(CosmetixApp(helper: h));
        await pumpUntil(t, find.text('Кабинет'));
        await _settle(t);
        final nav = t.state<NavigatorState>(find.byType(Navigator).first);
        nav.pushNamed(AppRoutes.care);
        await _settle(t);
        await t.tap(find.text('Вечер'));
        await _settle(t);
        expect(find.text('Совместимость средств'), findsOneWidget);
        expect(find.textContaining('ретиноиды и кислоты'), findsOneWidget);
      },
    );
  });

  test('the product page items: this product vs the bag', () async {
    final h = DatabaseHelper(path: inMemoryDatabasePath);
    addTearDown(h.close);
    final all = await ProductRepository(h).getAll(1);
    final cushion = RoutineItem.fromProduct(
      all.firstWhere((p) => p.name.contains('Magic Cushion')),
    );
    final nivea = RoutineItem.fromProduct(
      all.firstWhere((p) => p.name.contains('Soft Moisturizing')),
    );
    final cerave = RoutineItem.fromProduct(
      all.firstWhere((p) => p.name.contains('Moisturizing Cream')),
    );
    expect(
      MakeupCompatibility.checkAll([cushion, nivea]).single.text,
      contains('Nivea'),
    );
    expect(MakeupCompatibility.checkAll([cushion, cerave]), isEmpty);
    // not blocked by a missing profile type
    expect(SkinType.sensitive.code, 'sensitive');
  });

  group('the real catalog: acids, retinol, vitamin C', () {
    late DatabaseHelper helper;
    late List<Product> all;

    setUp(() async {
      helper = DatabaseHelper(path: inMemoryDatabasePath);
      all = await ProductRepository(helper).getAll(1);
    });
    tearDown(() => helper.close());

    RoutineItem item(String name) =>
        RoutineItem.fromProduct(all.firstWhere((p) => p.name.contains(name)));

    test('every product carries the actives its INCI list names', () {
      expect(item('Glycolic').actives, contains('glycolic'));
      expect(item('Retinol 0.5%').actives, contains('retinoid'));
      expect(item('BHA Blackhead').actives, contains('salicylic'));
      expect(item('Vitamin Drop').actives, contains('vitamin_c'));
      expect(item('Niacinamide 10%').actives, contains('niacinamide'));
    });

    test('real pairs: the right verdicts', () {
      IssueSeverity? verdict(String a, String b) {
        final r = ActiveRules.check([item(a), item(b)]);
        return r.isEmpty ? null : r.single.severity;
      }

      expect(verdict('Retinol 0.5%', 'Glycolic'), IssueSeverity.avoid);
      expect(verdict('Retinol 0.5%', 'BHA Blackhead'), IssueSeverity.avoid);
      expect(verdict('Retinol 0.5%', 'Vitamin Drop'), IssueSeverity.caution);
      expect(verdict('Glycolic', 'Vitamin Drop'), IssueSeverity.caution);
      expect(verdict('Glycolic', 'BHA Blackhead'), IssueSeverity.caution);
      // nothing to say about friendly combinations
      expect(verdict('Niacinamide 10%', 'Vitamin Drop'), isNull);
      expect(verdict('Niacinamide 10%', 'Retinol 0.5%'), isNull);
      expect(verdict('Moisturizing Cream', 'Retinol 0.5%'), isNull);
    });

    test('a sensitive skin gets a patch test for every active product', () {
      for (final n in [
        'Glycolic',
        'Retinol 0.5%',
        'BHA Blackhead',
        'Vitamin Drop',
      ]) {
        expect(
          PatchTestAdvice.forItems([item(n)], sensitive: true),
          isNotEmpty,
          reason: n,
        );
      }
      expect(
        PatchTestAdvice.forItems([item('Niacinamide 10%')], sensitive: true),
        isEmpty,
      );
    });

    test('the migration adds the new products to an older database', () async {
      final db = await helper.database;
      // what a database of the previous release looks like
      await db.delete('products', where: 'id >= 19');
      expect((await db.query('products')).length, 18);
      // a product of the user that happens to use id 19 must stay alone
      await db.insert('products', {
        'id': 19,
        'brand': 'My shop',
        'name': 'Мой товар',
        'category': 'Макияж',
        'price': 1,
        'color': 0,
        'created_at': 0,
      });
      await SeedData.applyNewProducts(db);
      expect(
        (await db.query('products', where: 'id = 19')).single['name'],
        'Мой товар',
      );
      expect((await db.query('products')).length, 18 + 1 + 3);
      // the others are complete: an offer in every shop, ingredients, traits
      final retinol =
          (await db.query(
                'products',
                where: "name LIKE 'Retinol 0.5%'",
              )).single['id']!
              as int;
      expect(
        (await db.query(
          'product_prices',
          where: 'product_id = ?',
          whereArgs: [retinol],
        )).length,
        13,
      );
      expect(
        (await db.query(
          'product_concerns',
          where: 'product_id = ?',
          whereArgs: [retinol],
        )).length,
        2,
      );
      // running it again changes nothing
      await SeedData.applyNewProducts(db);
      expect((await db.query('products')).length, 18 + 1 + 3);
    });
  });

  group('screens with real products', () {
    Future<void> boot(WidgetTester t, DatabaseHelper h) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      addTearDown(() => t.runAsync(h.close));
      await t.runAsync(() => UserRepository(h).setCurrentUser(1));
      await t.pumpWidget(CosmetixApp(helper: h));
      await pumpUntil(t, find.text('Кабинет'));
      await _settle(t);
    }

    testWidgets('the cart: conflict, patch test for a sensitive skin', (
      t,
    ) async {
      final h = DatabaseHelper(path: inMemoryDatabasePath);
      await t.runAsync(() async {
        final db = await h.database;
        await db.update('users', {
          'skin_type': 'Чувствительная',
        }, where: 'id = 1');
        final cart = CartRepository(h);
        for (final id in [19, 20, 12]) {
          await cart.add(1, id, 1);
        }
      });
      await boot(t, h);
      await t.tap(find.byIcon(Icons.shopping_cart_outlined).last);
      await _settle(t);
      expect(find.text('Перед покупкой'), findsOneWidget);
      expect(find.textContaining('ретиноиды и кислоты'), findsOneWidget);
      expect(find.textContaining('Сразу 3 средств'), findsOneWidget);
    });

    testWidgets('the cart of a normal skin: only the real conflict', (t) async {
      final h = DatabaseHelper(path: inMemoryDatabasePath);
      await t.runAsync(() async {
        final db = await h.database;
        await db.update('users', {'skin_type': 'Нормальная'}, where: 'id = 1');
        final cart = CartRepository(h);
        for (final id in [19, 20, 12]) {
          await cart.add(1, id, 1);
        }
      });
      await boot(t, h);
      await t.tap(find.byIcon(Icons.shopping_cart_outlined).last);
      await _settle(t);
      expect(find.textContaining('ретиноиды и кислоты'), findsOneWidget);
      expect(find.textContaining('Сразу'), findsNothing);
    });

    testWidgets(
      'a foundation page: the cream in the bag under it, and what fits',
      (t) async {
        final h = DatabaseHelper(path: inMemoryDatabasePath);
        await t.runAsync(() async {
          await CareRepository(h).addToBag(
            1,
            const MyProduct(
              id: 0,
              name: 'Soft Moisturizing Creme',
              brand: 'Nivea',
              category: 'Тело и ванна',
              productId: 15,
            ),
          );
        });
        await boot(t, h);
        final nav = t.state<NavigatorState>(find.byType(Navigator).first);
        nav.pushNamed(AppRoutes.product, arguments: 10);
        await _settle(t);
        await t.scrollUntilVisible(
          find.text('Сочетание с вашим уходом'),
          300,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.text('Сочетание с вашим уходом'), findsOneWidget);
        expect(find.textContaining('на маслах под'), findsOneWidget);
        await t.scrollUntilVisible(
          find.text('С чем сочетать'),
          300,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.text('С чем сочетать'), findsOneWidget);
      },
    );

    testWidgets('a retinol page: a conflict with the bag and a patch test', (
      t,
    ) async {
      final h = DatabaseHelper(path: inMemoryDatabasePath);
      await t.runAsync(() async {
        final db = await h.database;
        await db.update('users', {
          'skin_type': 'Чувствительная',
        }, where: 'id = 1');
        await CareRepository(h).addToBag(
          1,
          const MyProduct(
            id: 0,
            name: 'Пилинг с гликолевой кислотой',
            category: 'Уход за лицом',
          ),
        );
      });
      await boot(t, h);
      final nav = t.state<NavigatorState>(find.byType(Navigator).first);
      nav.pushNamed(AppRoutes.product, arguments: 20);
      await _settle(t);
      await t.scrollUntilVisible(
        find.text('Сочетание с вашим уходом'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.textContaining('ретиноиды и кислоты'), findsOneWidget);
      expect(
        find.textContaining('содержит активные компоненты'),
        findsOneWidget,
      );
    });
  });

  test('every text the checks can show is translated (EN and KK)', () {
    final siFd = _item(
      'F',
      base: FormulaBase.silicone,
      foundation: true,
      skincare: false,
    );
    final wFd = _item(
      'F',
      base: FormulaBase.water,
      foundation: true,
      skincare: false,
    );
    final all = <RoutineIssue>[
      ...ActiveRules.check([
        _item('A', actives: {'retinoid'}),
        _item('B', actives: {'glycolic'}),
      ]),
      ...ActiveRules.check([
        _item('A', actives: {'retinoid'}),
        _item('B', actives: {'benzoyl'}),
      ]),
      ...ActiveRules.check([
        _item('A', actives: {'retinoid'}),
        _item('B', actives: {'vitamin_c'}),
      ]),
      ...ActiveRules.check([
        _item('A', actives: {'vitamin_c'}),
        _item('B', actives: {'glycolic'}),
      ]),
      ...ActiveRules.check([
        _item('A', actives: {'benzoyl'}),
        _item('B', actives: {'vitamin_c'}),
      ]),
      ...ActiveRules.check([
        _item('A', actives: {'glycolic'}),
        _item('B', actives: {'salicylic'}),
      ]),
      ...ActiveRules.check([
        _item('A', actives: {'retinoid'}),
        _item('B', actives: {'retinoid'}),
      ]),
      ?MakeupCompatibility.check(_item('U', base: FormulaBase.oil), siFd),
      ?MakeupCompatibility.check(_item('U', base: FormulaBase.silicone), wFd),
      ?MakeupCompatibility.check(_item('U', base: FormulaBase.oil), wFd),
      ...PatchTestAdvice.forItems([
        _item('A', actives: {'retinoid'}),
        _item('B'),
        _item('C'),
      ], sensitive: true),
    ];
    expect(all.length, 12); // every rule was reached
    final keys = {
      for (final i in all) i.template,
      for (final b in FormulaBase.values)
        if (b.label.isNotEmpty) b.label,
      'Формула: {v0}',
      'Бензоилпероксид',
      'Совместимость средств',
      'Не используйте эти средства вместе',
      'Перед покупкой',
      'Сочетание с вашим уходом',
      'С чем сочетать',
      'Основа {v0}: эти средства из каталога ложатся под неё ровно, без скольжения и катышков.',
    };
    for (final k in keys) {
      expect(translationsEn[k], isNotNull, reason: 'EN: $k');
      expect(translationsKk[k], isNotNull, reason: 'KK: $k');
      // the placeholders survive the translation
      for (final ph in RegExp(r'\{\w+\}').allMatches(k).map((m) => m[0]!)) {
        expect(translationsEn[k], contains(ph), reason: 'EN $ph in $k');
        expect(translationsKk[k], contains(ph), reason: 'KK $ph in $k');
      }
    }
  });
}
