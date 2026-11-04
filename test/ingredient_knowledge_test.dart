import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/app.dart';
import 'package:cosmetix/core/i18n/translations_en.dart';
import 'package:cosmetix/core/i18n/translations_kk.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/repositories/product_repository.dart';
import 'package:cosmetix/repositories/user_repository.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/services/fragrance_allergen_names.dart';
import 'package:cosmetix/services/fragrance_allergens.dart';
import 'package:cosmetix/services/ingredient_catalog.dart';
import 'package:cosmetix/services/routine_checks.dart';
import 'widget_test.dart' show pumpUntil;

Map<String, dynamic> _json(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  group('fragrance allergens of the EU list', () {
    final doc = _json('data/fragrance_allergens.json');
    final entries = (doc['entries'] as List).cast<Map<String, dynamic>>();

    test('the data file is the 81 entries of the annex, with its source', () {
      expect(doc['count'], 81);
      expect(entries.length, 81);
      expect(doc['source'], contains('02009R1223'));
      expect(doc['amended_by'], contains('2023/1545'));
      final names = {
        for (final e in entries)
          for (final n in (e['inci'] as List)) (n as String).toLowerCase(),
      };
      // the well-known ones, straight from the official table
      for (final n in [
        'linalool',
        'limonene',
        'citronellol',
        'geraniol',
        'eugenol',
        'coumarin',
        'benzyl salicylate',
        'benzyl benzoate',
        'hexyl cinnamal',
        'citral',
        'geranial',
        'neral',
      ]) {
        expect(names, contains(n));
      }
    });

    test('the Dart list is generated from the data file (in sync)', () {
      final fromJson = {
        for (final e in entries)
          for (final n in (e['inci'] as List)) (n as String).toLowerCase(),
      };
      expect(fragranceAllergenNames.toSet(), fromJson);
    });

    test('names are found in a composition, brackets and case ignored', () {
      const inci =
          'Aqua, Glycerin, Parfum, Limonene, LINALOOL, '
          'Citrus Limon (Lemon) Peel Oil, Limonene, Alcohol';
      expect(FragranceAllergens.inProduct(inci), [
        'Limonene',
        'LINALOOL',
        'Citrus Limon (Lemon) Peel Oil',
      ]);
      expect(
        FragranceAllergens.inProduct('Aqua, Glycerin, Dimethicone'),
        isEmpty,
      );
      expect(FragranceAllergens.inProduct(''), isEmpty);
      // "Parfum" is the fragrance itself, not a named allergen
      expect(FragranceAllergens.isAllergen('Parfum'), isFalse);
    });

    test('the composition filter finds them too', () {
      Set<String> of(String inci) => IngredientCatalog.detect(inci);
      expect(of('Aqua, Limonene'), contains('fragrance_allergen'));
      expect(
        of('Aqua, Citrus Limon (Lemon) Peel Oil'),
        contains('fragrance_allergen'),
      );
      expect(of('Aqua, Glycerin'), isNot(contains('fragrance_allergen')));
      final g = IngredientCatalog.byCode('fragrance_allergen')!;
      expect(g.kind, IngredientKind.avoid);
      expect(translationsEn.containsKey(g.label), isTrue);
      expect(translationsKk.containsKey(g.label), isTrue);
    });

    test('real catalog: products with a listed allergen are found', () async {
      final h = DatabaseHelper(path: inMemoryDatabasePath);
      addTearDown(h.close);
      final all = await ProductRepository(h).getAll(1);
      final flagged = [
        for (final p in all)
          if (FragranceAllergens.inProduct(p.inci).isNotEmpty) p,
      ];
      expect(flagged, isNotEmpty);
      // the filter and the note agree on every product
      for (final p in all) {
        expect(
          IngredientCatalog.of(p).contains('fragrance_allergen'),
          FragranceAllergens.inProduct(p.inci).isNotEmpty,
          reason: p.name,
        );
      }
      expect(
        flagged.any((p) => p.inci.toLowerCase().contains('benzyl salicylate')),
        isTrue,
      );
    });
  });

  group('the data files agree with the code', () {
    test('active compatibility: every pair of the file', () {
      final doc = _json('data/active_compatibility.json');
      final names = (doc['ingredients'] as Map).keys.cast<String>().toList();
      expect(names.length, 13);
      final status = <String, String>{
        for (final p in (doc['pairs'] as List).cast<Map<String, dynamic>>())
          '${p['a']}|${p['b']}': p['status'] as String,
      };
      expect(status.length, 21);
      for (var i = 0; i < names.length; i++) {
        for (var j = i + 1; j < names.length; j++) {
          final want = status['${names[i]}|${names[j]}'] ?? 'ok';
          final r = ActiveRules.check([
            RoutineItem(title: names[i], actives: {names[i]}),
            RoutineItem(title: names[j], actives: {names[j]}),
          ]);
          switch (want) {
            case 'ok':
              expect(r, isEmpty, reason: '${names[i]}+${names[j]}');
            case 'care':
              expect(r.single.text, contains('с осторожностью'));
            case 'sep':
              expect(r.single.text, contains('разнести'));
            default:
              fail('unknown status $want');
          }
        }
      }
    });

    test('layering rules: kept ones fire, the removed one does not', () {
      final doc = _json('data/layering_rules.json');
      FormulaBase base(String s) => FormulaBase.values.firstWhere(
        (b) =>
            {
              'silicone': FormulaBase.silicone,
              'oil': FormulaBase.oil,
              'water': FormulaBase.water,
            }[s] ==
            b,
      );
      RoutineItem care(String b) => RoutineItem(title: 'care', base: base(b));
      RoutineItem fd(String b) => RoutineItem(
        title: 'fd',
        base: base(b),
        isFoundation: true,
        isSkincare: false,
      );
      for (final r in (doc['rules'] as List).cast<Map<String, dynamic>>()) {
        expect(
          MakeupCompatibility.check(care(r['under']), fd(r['over'])),
          isNotNull,
          reason: '${r['under']} under ${r['over']}',
        );
        expect((r['sources'] as List), isNotEmpty);
      }
      for (final r in (doc['removed'] as List).cast<Map<String, dynamic>>()) {
        expect(
          MakeupCompatibility.check(care(r['under']), fd(r['over'])),
          isNull,
        );
      }
    });
  });

  testWidgets('the product page names the allergens of the EU list', (t) async {
    final h = DatabaseHelper(path: inMemoryDatabasePath);
    t.view.physicalSize = const Size(1080, 7000);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    addTearDown(() => t.runAsync(h.close));
    final id = (await t.runAsync(() async {
      final all = await ProductRepository(h).getAll(1);
      return all
          .firstWhere((p) => p.inci.toLowerCase().contains('benzyl salicylate'))
          .id;
    }))!;
    await t.runAsync(() => UserRepository(h).setCurrentUser(1));
    await t.pumpWidget(CosmetixApp(helper: h));
    await pumpUntil(t, find.text('Кабинет'));
    for (var i = 0; i < 8; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await t.pump(const Duration(milliseconds: 100));
    }
    t
        .state<NavigatorState>(find.byType(Navigator).first)
        .pushNamed(AppRoutes.product, arguments: id);
    for (var i = 0; i < 8; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(
      find.textContaining('Ароматические аллергены (список ЕС)'),
      findsOneWidget,
    );
    expect(find.textContaining('Benzyl Salicylate'), findsWidgets);
    // a list of EU allergens is never called "safe"
    expect(find.text('Безопасный состав'), findsNothing);
    expect(find.text('Состав требует внимания'), findsOneWidget);
  });
}
