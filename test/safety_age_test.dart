import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/app.dart';
import 'package:cosmetix/core/beauty/beauty_codes.dart';
import 'package:cosmetix/core/i18n/translations_en.dart';
import 'package:cosmetix/core/i18n/translations_kk.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/models/app_user.dart';
import 'package:cosmetix/models/beauty_profile.dart';
import 'package:cosmetix/providers/cart_provider.dart';
import 'package:cosmetix/repositories/cart_repository.dart';
import 'package:cosmetix/repositories/product_repository.dart';
import 'package:cosmetix/repositories/user_repository.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/services/age_safety.dart';
import 'package:cosmetix/services/ingredient_catalog.dart';
import 'package:cosmetix/services/recommendation_service.dart';
import 'package:cosmetix/services/routine_checks.dart';
import 'widget_test.dart' show pumpUntil;

RoutineItem _item(String title, Set<String> actives) =>
    RoutineItem(title: title, actives: actives);

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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('age from the year of birth', () {
    final now = DateTime(2026, 11, 4);

    test('the careful age is one year lower (the birthday may be ahead)', () {
      expect(AgeSafety.ageFromBirthYear(2015, now: now), 10);
      expect(AgeSafety.ageFromBirthYear(2000, now: now), 25);
      expect(AgeSafety.ageFromBirthYear(2026, now: now), 0);
      expect(AgeSafety.ageFromBirthYear(null, now: now), isNull);
    });

    test('only a real year of birth is accepted', () {
      expect(AgeSafety.validBirthYear(2000, now: now), isTrue);
      expect(AgeSafety.validBirthYear(2026, now: now), isTrue);
      expect(AgeSafety.validBirthYear(2027, now: now), isFalse);
      expect(AgeSafety.validBirthYear(1800, now: now), isFalse);
    });
  });

  group('limits for strong actives', () {
    test('a child under 12 gets no retinoid or benzoyl peroxide', () {
      for (final a in ['retinoid', 'benzoyl']) {
        expect(AgeSafety.blocks(11, {a}), isTrue, reason: a);
        expect(AgeSafety.blocks(5, {a}), isTrue, reason: a);
        expect(AgeSafety.blocks(12, {a}), isFalse, reason: a);
      }
      // mild actives stay available, acids are a note and not a ban
      expect(AgeSafety.blocks(11, {'vitamin_c', 'hyaluronic'}), isFalse);
      expect(AgeSafety.blocks(11, {'glycolic', 'salicylic'}), isFalse);
      expect(AgeSafety.blocks(11, const {}), isFalse);
    });

    test('a child gets an "ask a doctor" note for an acid, not a ban', () {
      final i = AgeSafety.issues(10, _item('Toner', {'glycolic'})).single;
      expect(i.severity, IssueSeverity.caution);
      expect(i.text, contains('сначала спросите врача'));
    });

    test('an adult, or an unknown age, is not restricted', () {
      for (final age in [12, 17, 25]) {
        expect(AgeSafety.issues(age, _item('R', {'retinoid'})), isEmpty);
      }
      expect(AgeSafety.issues(null, _item('R', {'retinoid'})), isEmpty);
      expect(AgeSafety.blocks(null, {'retinoid'}), isFalse);
    });

    test('a child sees a "do not use" warning', () {
      final i = AgeSafety.issues(11, _item('Retinol', {'retinoid'})).single;
      expect(i.severity, IssueSeverity.avoid);
      expect(i.text, contains('до 12 лет'));
      expect(i.text, contains('Retinol'));
    });
  });

  group('notice about strong actives', () {
    test('retinoid, acid and benzoyl peroxide each get their advice', () {
      final r = ActiveNotice.forItem(_item('R', {'retinoid'})).single.text;
      expect(r, allOf(contains('SPF 30+'), contains('беременности')));
      final a = ActiveNotice.forItem(_item('A', {'glycolic'})).single.text;
      expect(a, allOf(contains('кислоту'), contains('SPF 30+')));
      final b = ActiveNotice.forItem(_item('B', {'benzoyl'})).single.text;
      expect(b, contains('бензоилпероксид'));
    });

    test('a mild or plain product has no notice', () {
      expect(ActiveNotice.forItem(_item('P', const {})), isEmpty);
      expect(ActiveNotice.forItem(_item('C', {'vitamin_c'})), isEmpty);
    });

    test('a sensitive skin gets the patch test in the same sentence', () {
      final plain = ActiveNotice.forItem(_item('R', {'retinoid'})).single.text;
      final sens = ActiveNotice.forItem(
        _item('R', {'retinoid'}),
        sensitive: true,
      ).single.text;
      expect(plain, isNot(contains('небольшой участок')));
      expect(sens, contains('на 3 дня нанесите на небольшой участок'));
    });

    test('every new text is translated (EN and KK)', () {
      final all = <RoutineIssue>[
        ...AgeSafety.issues(11, _item('A', {'retinoid'})),
        ...AgeSafety.issues(11, _item('A', {'glycolic'})),
        for (final s in [false, true]) ...[
          ...ActiveNotice.forItem(_item('A', {'retinoid'}), sensitive: s),
          ...ActiveNotice.forItem(_item('A', {'glycolic'}), sensitive: s),
          ...ActiveNotice.forItem(_item('A', {'benzoyl'}), sensitive: s),
        ],
      ];
      expect(all.length, 8);
      final keys = {
        for (final i in all) i.template,
        'Это средство с ретиноидом или бензоилпероксидом не подходит в вашем возрасте. Спросите врача.',
        'Год рождения (необязательно)',
        'Введите год рождения, например 2000',
        'Нужен для безопасности: детям до 12 лет не предлагают ретиноиды и бензоилпероксид.',
        'Как кожа сейчас после умывания?',
        'Кожа меняется: проверьте, не стала ли она суше. Ответ обновит подбор и предупреждения.',
        'Тип кожи: {t}',
      };
      for (final k in keys) {
        expect(translationsEn.containsKey(k), isTrue, reason: 'EN: $k');
        expect(translationsKk.containsKey(k), isTrue, reason: 'KK: $k');
      }
    });
  });

  group('database and profile', () {
    test(
      'the year of birth is saved, read as an age and can be cleared',
      () async {
        final h = DatabaseHelper(path: inMemoryDatabasePath);
        addTearDown(h.close);
        final users = UserRepository(h);
        Future<AppUser> save(int? year) async {
          await users.updateProfile(
            id: 1,
            firstName: 'А',
            lastName: 'Б',
            email: 'a@b.kz',
            phone: '',
            city: '',
            birthYear: year,
          );
          return (await users.getById(1))!;
        }

        final child = await save(DateTime.now().year - 11);
        expect(child.birthYear, DateTime.now().year - 11);
        expect(child.age, 10); // the careful age
        expect(child.beautyProfile.age, 10);
        final cleared = await save(null);
        expect(cleared.birthYear, isNull);
        expect(cleared.age, isNull);
      },
    );

    test('the age is part of the profile signature (re-ranks the catalog)', () {
      const a = BeautyProfile(age: 10);
      const b = BeautyProfile(age: 30);
      expect(a.signature, isNot(b.signature));
    });

    test('the skin question is asked again after 30 days', () {
      AppUser user({int? done, String color = 'Весна'}) => AppUser(
        id: 1,
        firstName: 'А',
        lastName: '',
        email: 'a@b.kz',
        colorType: color,
        beautyCompletedAt: done,
      );
      final now = DateTime(2026, 11, 4);
      final recent = now.subtract(const Duration(days: 5));
      final old = now.subtract(const Duration(days: 45));
      expect(
        user(done: recent.millisecondsSinceEpoch).skinCheckDue(now: now),
        isFalse,
      );
      expect(
        user(done: old.millisecondsSinceEpoch).skinCheckDue(now: now),
        isTrue,
      );
      expect(user().skinCheckDue(now: now), isTrue);
      // no Beauty Test yet: nothing to refresh
      expect(user(color: '').skinCheckDue(now: now), isFalse);
    });
  });

  group('recommendations and cart for a child', () {
    late DatabaseHelper h;
    setUp(() => h = DatabaseHelper(path: inMemoryDatabasePath));
    tearDown(() => h.close());

    test('strong actives disappear from the picks of a child', () async {
      final candidates = await ProductRepository(h).candidates(1);
      List<int> ids(int? age) => [
        for (final r in RecommendationService.rank(
          candidates: candidates,
          profile: BeautyProfile(age: age),
          blacklist: const [],
        ))
          r.product.id,
      ];
      final strong = {
        for (final c in candidates)
          if (AgeSafety.blocks(10, IngredientCatalog.of(c.product)))
            c.product.id,
      };
      expect(strong, isNotEmpty, reason: 'the catalog has retinol and acids');
      final adult = ids(30);
      final child = ids(10);
      expect(adult.toSet().containsAll(strong), isTrue);
      expect(child.toSet().intersection(strong), isEmpty);
      expect(child.length, adult.length - strong.length);
    });

    test(
      'the cart refuses a strong product for a child, not for an adult',
      () async {
        final products = await ProductRepository(h).getAll(1);
        final strong = products.firstWhere(
          (p) => AgeSafety.blocks(10, IngredientCatalog.of(p)),
        );
        final mild = products.firstWhere(
          (p) => p.inStock && !AgeSafety.blocks(10, IngredientCatalog.of(p)),
        );
        final cart = CartProvider(CartRepository(h))
          ..guard = (p) => AgeSafety.blockReason(10, p);
        await cart.load(1);
        expect(await cart.add(strong), isNotNull);
        expect(cart.contains(strong.id), isFalse);
        expect(await cart.add(mild), isNull);
        cart.guard = (p) => AgeSafety.blockReason(30, p);
        expect(await cart.add(strong), isNull);
        expect(cart.contains(strong.id), isTrue);
      },
    );
  });

  group('screens', () {
    Future<void> boot(
      WidgetTester t,
      DatabaseHelper h, {
      Map<String, Object?> user = const {},
    }) async {
      t.view.physicalSize = const Size(1080, 2400);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      addTearDown(() => t.runAsync(h.close));
      if (user.isNotEmpty) {
        await t.runAsync(() async {
          final db = await h.database;
          await db.update('users', user, where: 'id = 1');
        });
      }
      await t.runAsync(() => UserRepository(h).setCurrentUser(1));
      await t.pumpWidget(CosmetixApp(helper: h));
      await pumpUntil(t, find.text('Кабинет'));
      await _settle(t);
    }

    NavigatorState nav(WidgetTester t) =>
        t.state<NavigatorState>(find.byType(Navigator).first);

    testWidgets('the retinol page warns a child and refuses the cart', (
      t,
    ) async {
      final h = DatabaseHelper(path: inMemoryDatabasePath);
      await boot(t, h, user: {'birth_year': DateTime.now().year - 11});
      nav(t).pushNamed(AppRoutes.product, arguments: 20);
      await _settle(t);
      await t.scrollUntilVisible(
        find.textContaining('детям до 12 лет'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('детям до 12 лет'), findsOneWidget);
      await t.tap(find.text('В корзину'));
      await _settle(t);
      expect(
        find.textContaining('не подходит в вашем возрасте'),
        findsOneWidget,
      );
      expect(find.textContaining('в корзине'), findsNothing);
    });

    testWidgets('an adult sees only the advice, and can buy', (t) async {
      final h = DatabaseHelper(path: inMemoryDatabasePath);
      await boot(t, h, user: {'birth_year': DateTime.now().year - 30});
      nav(t).pushNamed(AppRoutes.product, arguments: 20);
      await _settle(t);
      await t.scrollUntilVisible(
        find.textContaining('содержит ретиноид'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('детям до 12 лет'), findsNothing);
      expect(
        find.textContaining('наносите солнцезащитное средство SPF 30+'),
        findsOneWidget,
      );
    });

    testWidgets('edit profile: the year of birth is checked and saved', (
      t,
    ) async {
      final h = DatabaseHelper(path: inMemoryDatabasePath);
      await boot(t, h);
      nav(t).pushNamed(AppRoutes.editProfile);
      await _settle(t);
      // the labels of the form are upper case
      expect(find.text('ГОД РОЖДЕНИЯ (НЕОБЯЗАТЕЛЬНО)'), findsOneWidget);
      final year = find.byType(TextFormField).at(5);

      await t.ensureVisible(year);
      await t.enterText(year, '1850');
      await t.tap(find.text('Сохранить изменения'));
      await _settle(t);
      expect(find.text('Введите год рождения, например 2000'), findsOneWidget);

      await t.enterText(year, '${DateTime.now().year - 12}');
      await t.tap(find.text('Сохранить изменения'));
      await _settle(t);
      final row = await t.runAsync(() async {
        final db = await h.database;
        return (await db.query('users', where: 'id = 1')).single;
      });
      expect(row!['birth_year'], DateTime.now().year - 12);
    });

    testWidgets('the profile asks again about the skin and saves the answer', (
      t,
    ) async {
      final h = DatabaseHelper(path: inMemoryDatabasePath);
      await boot(t, h);
      await t.tap(find.text('Кабинет'));
      await _settle(t);
      await t.ensureVisible(find.text('Кожа стянута, появляется шелушение'));
      await _settle(t);
      expect(find.text('Как кожа сейчас после умывания?'), findsOneWidget);
      await t.tap(find.text('Кожа стянута, появляется шелушение'));
      await _settle(t);
      final row = await t.runAsync(() async {
        final db = await h.database;
        return (await db.query('users', where: 'id = 1')).single;
      });
      expect(row!['skin_type'], SkinType.dry.label);
      expect(row['beauty_completed_at'], isNotNull);
      // answered: the card goes away
      expect(find.text('Как кожа сейчас после умывания?'), findsNothing);
    });
  });
}
