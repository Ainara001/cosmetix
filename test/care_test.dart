import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/models/care_models.dart';
import 'package:cosmetix/providers/care_provider.dart';
import 'package:cosmetix/repositories/care_repository.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('dates', () {
    test('addMonths clamps to the end of the month', () {
      expect(addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
      expect(addMonths(DateTime(2028, 1, 31), 1), DateTime(2028, 2, 29));
      expect(addMonths(DateTime(2026, 10, 22), 12), DateTime(2027, 10, 22));
      expect(addMonths(DateTime(2026, 11, 15), 3), DateTime(2027, 2, 15));
    });

    test('day keys round-trip', () {
      expect(dayKey(DateTime(2026, 3, 5)), '2026-03-05');
      expect(parseDayKey('2026-03-05'), DateTime(2026, 3, 5));
    });
  });

  group('shelf life reminder', () {
    final now = DateTime(2026, 10, 22);
    MyProduct p({DateTime? opened, int? pao, DateTime? expires}) => MyProduct(
      id: 1,
      name: 'Крем',
      openedAt: opened,
      paoMonths: pao,
      expiresAt: expires,
    );

    test('no package data: nothing is promised', () {
      expect(p().useUntil, isNull);
      expect(p().expiry(now), ExpiryState.unknown);
      // an opening date alone is not enough either
      expect(p(opened: DateTime(2026, 9, 1)).expiry(now), ExpiryState.unknown);
      expect(p(pao: 12).expiry(now), ExpiryState.unknown);
    });

    test('opened + period after opening', () {
      final x = p(opened: DateTime(2026, 4, 22), pao: 6);
      expect(x.useUntil, DateTime(2026, 10, 22));
      expect(x.daysLeft(now), 0);
      expect(x.expiry(now), ExpiryState.soon); // ends today
      expect(
        p(opened: DateTime(2026, 4, 21), pao: 6).expiry(now),
        ExpiryState.expired,
      );
      expect(
        p(opened: DateTime(2026, 10, 1), pao: 12).expiry(now),
        ExpiryState.ok,
      );
    });

    test('the printed date wins when it is earlier', () {
      final x = p(
        opened: DateTime(2026, 10, 1),
        pao: 24,
        expires: DateTime(2026, 11, 10),
      );
      expect(x.useUntil, DateTime(2026, 11, 10));
      expect(x.daysLeft(now), 19);
      expect(x.expiry(now), ExpiryState.soon);
    });

    test('30 days is "soon", 31 is fine', () {
      expect(p(expires: DateTime(2026, 11, 21)).expiry(now), ExpiryState.soon);
      expect(p(expires: DateTime(2026, 11, 22)).expiry(now), ExpiryState.ok);
    });
  });

  group('validation', () {
    final now = DateTime(2026, 10, 22);
    MyProduct make({
      String name = 'Крем',
      DateTime? bought,
      DateTime? opened,
      int? pao,
    }) => MyProduct(
      id: 0,
      name: name,
      purchasedAt: bought,
      openedAt: opened,
      paoMonths: pao,
    );

    test('name is required', () {
      expect(CareProvider.validate(make(name: ' '), now: now), isNotNull);
      expect(CareProvider.validate(make(), now: now), isNull);
    });

    test('dates can not be in the future or contradict each other', () {
      expect(
        CareProvider.validate(make(bought: DateTime(2026, 12, 1)), now: now),
        isNotNull,
      );
      expect(
        CareProvider.validate(make(opened: DateTime(2026, 12, 1)), now: now),
        isNotNull,
      );
      expect(
        CareProvider.validate(
          make(bought: DateTime(2026, 5, 1), opened: DateTime(2026, 4, 1)),
          now: now,
        ),
        isNotNull,
      );
      expect(
        CareProvider.validate(
          make(bought: DateTime(2026, 4, 1), opened: DateTime(2026, 5, 1)),
          now: now,
        ),
        isNull,
      );
    });

    test('a period after opening needs an opening date', () {
      expect(CareProvider.validate(make(pao: 12), now: now), isNotNull);
      expect(
        CareProvider.validate(
          make(opened: DateTime(2026, 5, 1), pao: 12),
          now: now,
        ),
        isNull,
      );
    });
  });

  group('cosmetic bag and care plan (SQLite)', () {
    late DatabaseHelper helper;
    late CareRepository repo;
    late CareProvider care;
    var clock = DateTime(2026, 10, 22, 8);

    setUp(() async {
      clock = DateTime(2026, 10, 22, 8);
      helper = DatabaseHelper(path: inMemoryDatabasePath);
      repo = CareRepository(helper);
      care = CareProvider(repo, clock: () => clock);
      await helper.database;
      await care.load(1);
    });
    tearDown(() => helper.close());

    MyProduct item(String name, {DateTime? opened, int? pao, DateTime? exp}) =>
        MyProduct(
          id: 0,
          name: name,
          brand: 'Brand',
          category: 'Уход за лицом',
          openedAt: opened,
          paoMonths: pao,
          expiresAt: exp,
        );

    test('add, edit and delete a product; data survives a reload', () async {
      expect(care.bag, isEmpty);
      expect(await care.saveProduct(item('Крем'), isNew: true), isNull);
      expect(care.bag.single.title, 'Brand — Крем');

      final saved = care.bag.single;
      final edited = MyProduct(
        id: saved.id,
        name: 'Крем 2',
        brand: 'Brand',
        category: 'Уход за лицом',
        purchasedAt: DateTime(2026, 5, 1),
        openedAt: DateTime(2026, 6, 1),
        paoMonths: 12,
        notes: 'заметка',
      );
      expect(await care.saveProduct(edited), isNull);
      final again = CareProvider(repo, clock: () => clock);
      await again.load(1);
      final back = again.bag.single;
      expect(back.name, 'Крем 2');
      expect(back.purchasedAt, DateTime(2026, 5, 1));
      expect(back.openedAt, DateTime(2026, 6, 1));
      expect(back.paoMonths, 12);
      expect(back.notes, 'заметка');
      expect(back.useUntil, DateTime(2027, 6, 1));

      await care.deleteProduct(back);
      expect(care.bag, isEmpty);
    });

    test('invalid products are not saved', () async {
      expect(await care.saveProduct(item(''), isNew: true), isNotNull);
      expect(care.bag, isEmpty);
    });

    test('reminders list expired and soon-to-expire products only', () async {
      await care.saveProduct(
        item('Старый', opened: DateTime(2025, 1, 1), pao: 6),
        isNew: true,
      );
      await care.saveProduct(
        item('Скоро', exp: DateTime(2026, 11, 5)),
        isNew: true,
      );
      await care.saveProduct(
        item('Свежий', exp: DateTime(2028, 1, 1)),
        isNew: true,
      );
      await care.saveProduct(item('Без данных'), isNew: true);
      expect(care.attention.map((p) => p.name).toSet(), {'Старый', 'Скоро'});
    });

    test('plan: add, no duplicates, reorder, remove', () async {
      await care.saveProduct(item('AA'), isNew: true);
      await care.saveProduct(item('BB'), isNew: true);
      await care.saveProduct(item('CC'), isNew: true);
      final byName = {for (final p in care.bag) p.name: p};
      expect(await care.addStep(CarePeriod.morning, byName['AA']!), isNull);
      expect(await care.addStep(CarePeriod.morning, byName['BB']!), isNull);
      expect(await care.addStep(CarePeriod.morning, byName['AA']!), isNotNull);
      expect(await care.addStep(CarePeriod.evening, byName['CC']!), isNull);

      List<String> names(CarePeriod p) => [
        for (final s in care.steps(p)) s.product.name,
      ];
      expect(names(CarePeriod.morning), ['AA', 'BB']);
      expect(names(CarePeriod.evening), ['CC']);

      await care.move(care.steps(CarePeriod.morning).last, -1);
      expect(names(CarePeriod.morning), ['BB', 'AA']);
      // moving past the ends does nothing
      await care.move(care.steps(CarePeriod.morning).first, -1);
      expect(names(CarePeriod.morning), ['BB', 'AA']);

      await care.removeStep(care.steps(CarePeriod.morning).first);
      expect(names(CarePeriod.morning), ['AA']);
    });

    test('marking used is per day and period, and kept in history', () async {
      await care.saveProduct(item('Сыворотка'), isNew: true);
      final p = care.bag.single;
      await care.addStep(CarePeriod.morning, p);
      await care.addStep(CarePeriod.evening, p);
      final morning = care.steps(CarePeriod.morning).single;
      final evening = care.steps(CarePeriod.evening).single;

      await care.setUsed(morning, true);
      expect(care.isUsedToday(CarePeriod.morning, p.id), isTrue);
      expect(care.isUsedToday(CarePeriod.evening, p.id), isFalse);
      expect(care.doneCount(CarePeriod.morning), 1);
      await care.setUsed(morning, true); // twice is still one mark
      expect(care.history.length, 1);

      await care.setUsed(evening, true);
      expect(care.history.length, 2);
      await care.setUsed(evening, false);
      expect(care.history.length, 1);

      // next day: the mark is gone, the history stays
      clock = DateTime(2026, 10, 23, 8);
      await care.load(1);
      expect(care.isUsedToday(CarePeriod.morning, p.id), isFalse);
      expect(care.history.single.productName, 'Brand — Сыворотка');
      expect(care.historyByDay.keys.single, DateTime(2026, 10, 22));
    });

    test(
      'deleting a product removes it from the plan, not from history',
      () async {
        await care.saveProduct(item('Тоник'), isNew: true);
        final p = care.bag.single;
        await care.addStep(CarePeriod.morning, p);
        await care.setUsed(care.steps(CarePeriod.morning).single, true);
        await care.deleteProduct(p);
        expect(care.steps(CarePeriod.morning), isEmpty);
        expect(care.history.single.productName, 'Brand — Тоник');
        expect(care.history.single.myProductId, isNull);
      },
    );

    test('history only covers the last 30 days', () async {
      await care.saveProduct(item('XX'), isNew: true);
      final p = care.bag.single;
      await repo.setUsed(
        userId: 1,
        day: DateTime(2026, 8, 1),
        period: CarePeriod.morning,
        product: p,
        used: true,
      );
      await repo.setUsed(
        userId: 1,
        day: DateTime(2026, 10, 10),
        period: CarePeriod.morning,
        product: p,
        used: true,
      );
      final h = await repo.history(1, now: DateTime(2026, 10, 22));
      expect(h.map((e) => e.day), [DateTime(2026, 10, 10)]);
    });

    test('data of one user is not visible to another', () async {
      await care.saveProduct(item('Мой'), isNew: true);
      final db = await helper.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.insert('users', {
        'first_name': 'B',
        'email': 'b@b.kz',
        'password_hash': 'x',
        'created_at': now,
        'updated_at': now,
      });
      final other = await db.query('users', where: "email = 'b@b.kz'");
      final otherId = other.single['id']! as int;
      expect(await repo.bag(otherId), isEmpty);
    });
  });
}
