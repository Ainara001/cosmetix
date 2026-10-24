import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/core/utils/app_paths.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/models/reaction_insights.dart';
import 'package:cosmetix/models/safety_models.dart';
import 'package:cosmetix/providers/safety_provider.dart';
import 'package:cosmetix/repositories/safety_repository.dart';
import 'package:cosmetix/widgets/reaction_history_list.dart';

Reaction reaction(
  int id,
  int productId, {
  String title = 'Покраснение и зуд',
  int severity = 3,
  DateTime? date,
}) => Reaction(
  id: id,
  productId: productId,
  productName: 'Продукт $productId',
  art: 'bottle',
  color: 0xFFF4B6C2,
  title: title,
  severity: severity,
  date: date ?? DateTime(2026, 5, id),
  notes: '',
);

Ingredient ing(String name, {int risk = 0, bool allergen = false}) =>
    Ingredient(
      id: name.hashCode,
      name: name,
      description: '',
      risk: risk,
      isAllergen: allergen,
    );

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('repeated observations', () {
    test('a product with 2+ records is reported, others are not', () {
      final r = ReactionInsights.compute([
        reaction(1, 10, severity: 2, date: DateTime(2026, 5, 1)),
        reaction(2, 10, severity: 4, date: DateTime(2026, 6, 1)),
        reaction(3, 11),
      ], {});
      expect(r.repeatedProducts.length, 1);
      final p = r.repeatedProducts.single;
      expect(p.productId, 10);
      expect(p.count, 2);
      expect(p.averageSeverity, 3.0);
      expect(p.firstDate, DateTime(2026, 5, 1));
      expect(p.lastDate, DateTime(2026, 6, 1));
    });

    test('shared ingredients: only cautionary ones, only in 2+ products', () {
      final r = ReactionInsights.compute(
        [reaction(1, 10), reaction(2, 11), reaction(3, 12)],
        {
          10: [ing('Aqua'), ing('Parfum', risk: 1), ing('SLS', risk: 2)],
          11: [ing('Aqua'), ing('Parfum', risk: 1)],
          12: [ing('Aqua'), ing('Salicylic', allergen: true)],
        },
      );
      expect(r.sharedIngredients.map((e) => e.name), ['Parfum']);
      expect(r.sharedIngredients.single.productCount, 2);
      expect(r.sharedIngredients.single.totalProducts, 3);
    });

    test('nothing repeats -> empty', () {
      final r = ReactionInsights.compute(
        [reaction(1, 10)],
        {
          10: [ing('Parfum', risk: 1)],
        },
      );
      expect(r.isEmpty, isTrue);
    });
  });

  group('diary records with history and photo', () {
    late Directory tmp;
    late DatabaseHelper helper;
    late SafetyRepository repo;
    late SafetyProvider safety;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('cosmetix_diary');
      AppPaths.setForTest(documents: tmp.path, databases: tmp.path);
      helper = DatabaseHelper(path: inMemoryDatabasePath);
      repo = SafetyRepository(helper);
      safety = SafetyProvider(repo);
      await helper.database;
      await safety.load(1);
    });
    tearDown(() async {
      await helper.close();
      AppPaths.setForTest();
      tmp.deleteSync(recursive: true);
    });

    Future<String> photoFile(String name) async {
      final src = File('${tmp.path}/src_$name')..writeAsStringSync('x');
      return AppPaths.storePhoto(src, AppPaths.reactionPhotosDir, prefix: name);
    }

    test('creating adds a history entry; the record keeps its photo', () async {
      final photo = await photoFile('a');
      await safety.saveReaction(
        productId: 5,
        title: 'Сыпь',
        severity: 2,
        date: DateTime(2026, 6, 1),
        photoPath: photo,
      );
      final r = safety.reactions.firstWhere((e) => e.title == 'Сыпь');
      expect(r.photoPath, photo);
      final h = await safety.reactionHistory(r.id);
      expect(h.single.created, isTrue);
      expect(describeReactionChange(h.single), ['Запись создана']);
    });

    test('editing records exactly what changed', () async {
      await safety.saveReaction(
        productId: 5,
        title: 'Сыпь',
        severity: 2,
        date: DateTime(2026, 6, 1),
        notes: 'a',
      );
      final r = safety.reactions.firstWhere((e) => e.title == 'Сыпь');
      await safety.saveReaction(
        id: r.id,
        productId: 5,
        title: 'Сыпь',
        severity: 4,
        date: DateTime(2026, 6, 3),
        notes: 'b',
      );
      final h = await safety.reactionHistory(r.id);
      expect(h.length, 2);
      final change = h.first; // newest first
      expect(change.created, isFalse);
      expect(change.fields.keys.toSet(), {'severity', 'date', 'notes'});
      expect(change.fields['severity'], ('2', '4'));
      expect(change.fields['date'], ('2026-06-01', '2026-06-03'));
      expect(describeReactionChange(change), contains('Тяжесть: 2 → 4'));
      expect(describeReactionChange(change), contains('Заметка изменена'));
    });

    test('saving without changes adds no history entry', () async {
      await safety.saveReaction(
        productId: 5,
        title: 'Сыпь',
        severity: 2,
        date: DateTime(2026, 6, 1),
      );
      final r = safety.reactions.firstWhere((e) => e.title == 'Сыпь');
      await safety.saveReaction(
        id: r.id,
        productId: 5,
        title: 'Сыпь',
        severity: 2,
        date: DateTime(2026, 6, 1),
      );
      expect((await safety.reactionHistory(r.id)).length, 1);
    });

    test('changing the product is recorded with both names', () async {
      await safety.saveReaction(
        productId: 5,
        title: 'Сыпь',
        severity: 2,
        date: DateTime(2026, 6, 1),
      );
      final r = safety.reactions.firstWhere((e) => e.title == 'Сыпь');
      await safety.saveReaction(
        id: r.id,
        productId: 6,
        title: 'Сыпь',
        severity: 2,
        date: DateTime(2026, 6, 1),
      );
      final change = (await safety.reactionHistory(r.id)).first;
      expect(change.fields.keys, ['product']);
      expect(change.fields['product']!.$1, isNot(change.fields['product']!.$2));
    });

    test(
      'replacing and removing the photo is recorded and deletes files',
      () async {
        final first = await photoFile('p1');
        await safety.saveReaction(
          productId: 5,
          title: 'Сыпь',
          severity: 2,
          date: DateTime(2026, 6, 1),
          photoPath: first,
        );
        final r = safety.reactions.firstWhere((e) => e.title == 'Сыпь');

        final second = await photoFile('p2');
        await safety.saveReaction(
          id: r.id,
          productId: 5,
          title: 'Сыпь',
          severity: 2,
          date: DateTime(2026, 6, 1),
          photoPath: second,
        );
        expect(File(first).existsSync(), isFalse); // old file gone
        expect(File(second).existsSync(), isTrue);
        var h = await safety.reactionHistory(r.id);
        expect(describeReactionChange(h.first), ['Фото заменено']);

        await safety.saveReaction(
          id: r.id,
          productId: 5,
          title: 'Сыпь',
          severity: 2,
          date: DateTime(2026, 6, 1),
        );
        expect(File(second).existsSync(), isFalse);
        h = await safety.reactionHistory(r.id);
        expect(describeReactionChange(h.first), ['Фото удалено']);
        expect(
          safety.reactions.firstWhere((e) => e.id == r.id).photoPath,
          isNull,
        );
      },
    );

    test('deleting a record deletes its photo and its history', () async {
      final photo = await photoFile('d');
      await safety.saveReaction(
        productId: 5,
        title: 'Сыпь',
        severity: 2,
        date: DateTime(2026, 6, 1),
        photoPath: photo,
      );
      final r = safety.reactions.firstWhere((e) => e.title == 'Сыпь');
      await safety.deleteReaction(r);
      expect(File(photo).existsSync(), isFalse);
      expect(await repo.reactionHistory(r.id), isEmpty);
    });

    test('insights use the real catalog ingredients', () async {
      // demo data has records for products 3, 4, 15; add a second for product 3
      await safety.saveReaction(
        productId: 3,
        title: 'Сыпь',
        severity: 2,
        date: DateTime(2026, 6, 1),
      );
      final ins = await safety.insights();
      expect(ins.repeatedProducts.map((p) => p.productId), contains(3));
    });
  });
}
