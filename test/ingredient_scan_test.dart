import 'package:flutter_test/flutter_test.dart';

import 'package:cosmetix/models/safety_models.dart';
import 'package:cosmetix/services/ingredient_scan/ingredient_matcher.dart';
import 'package:cosmetix/services/ingredient_scan/ingredient_text_parser.dart';

BlacklistItem item(
  String name, {
  String? group,
  bool enabled = true,
  bool custom = false,
}) => BlacklistItem(
  id: name.hashCode,
  name: name,
  description: 'd',
  enabled: enabled,
  isCustom: custom,
  groupKey: group,
);

void main() {
  group('parser', () {
    test('English label with a start marker and a stop marker', () {
      final r = IngredientTextParser.parse(
        'Ingredients: Aqua, Glycerin, Methylparaben, Parfum.\n'
        'Directions: apply twice a day. Made in Korea',
      );
      expect(r, ['Aqua', 'Glycerin', 'Methylparaben', 'Parfum']);
    });

    test('Russian label', () {
      final r = IngredientTextParser.parse(
        'Состав: Вода, Глицерин; Диметикон, Токоферол.\nСрок годности: 24 мес.',
      );
      expect(r, ['Вода', 'Глицерин', 'Диметикон', 'Токоферол']);
    });

    test('OCR output with line breaks inside the list', () {
      final r = IngredientTextParser.parse(
        'INGREDIENTS:\nAqua, Sodium Laureth\nSulfate, Cocamidopropyl\nBetaine, Phenoxyethanol',
      );
      expect(r, [
        'Aqua',
        'Sodium Laureth Sulfate',
        'Cocamidopropyl Betaine',
        'Phenoxyethanol',
      ]);
    });

    test('a word split with a hyphen at the end of a line is re-joined', () {
      final r = IngredientTextParser.parse('Aqua, Methyl-\nparaben, Glycerin');
      expect(r, ['Aqua', 'Methylparaben', 'Glycerin']);
    });

    test('commas inside brackets do not split an ingredient', () {
      final r = IngredientTextParser.parse(
        'Aqua (Water, Eau), Glycerin, CI 77891 (Titanium Dioxide)',
      );
      expect(r, [
        'Aqua (Water, Eau)',
        'Glycerin',
        'CI 77891 (Titanium Dioxide)',
      ]);
    });

    test('one ingredient per line without commas', () {
      expect(IngredientTextParser.parse('Aqua\nGlycerin\nParfum'), [
        'Aqua',
        'Glycerin',
        'Parfum',
      ]);
    });

    test('duplicates, junk, numbers and leading "and" are cleaned', () {
      final r = IngredientTextParser.parse(
        'Aqua, aqua, 12345, -, ., and Fragrance, •Glycerin•, x',
      );
      expect(r, ['Aqua', 'Fragrance', 'Glycerin']);
    });

    test('empty and unreadable text gives an empty list', () {
      expect(IngredientTextParser.parse(''), isEmpty);
      expect(IngredientTextParser.parse('  \n  '), isEmpty);
      expect(IngredientTextParser.parse('!!! ??? 123'), isEmpty);
    });

    test('a very long garbage "ingredient" is dropped', () {
      final r = IngredientTextParser.parse('Aqua, ${'x' * 200}, Glycerin');
      expect(r, ['Aqua', 'Glycerin']);
    });

    test('a huge list is capped', () {
      final text = List.generate(400, (i) => 'Item$i').join(', ');
      expect(
        IngredientTextParser.parse(text).length,
        IngredientTextParser.maxItems,
      );
    });
  });

  group('group names', () {
    test('parabens', () {
      for (final n in ['Methylparaben', 'Propyl Paraben', 'парабены']) {
        expect(IngredientMatcher.inGroup(n, 'paraben'), isTrue, reason: n);
      }
      expect(IngredientMatcher.inGroup('Aqua', 'paraben'), isFalse);
    });

    test('sulfates: SLS/SLES yes, magnesium sulfate no', () {
      for (final n in [
        'Sodium Lauryl Sulfate',
        'Sodium Laureth Sulfate',
        'Ammonium Lauryl Sulfate',
        'SLS',
        'SLES',
        'Лаурилсульфат натрия',
      ]) {
        expect(IngredientMatcher.inGroup(n, 'sulfate'), isTrue, reason: n);
      }
      expect(
        IngredientMatcher.inGroup('Magnesium Sulfate', 'sulfate'),
        isFalse,
      );
      expect(IngredientMatcher.inGroup('Zinc Sulfate', 'sulfate'), isFalse);
    });

    test('silicones', () {
      for (final n in [
        'Dimethicone',
        'Cyclopentasiloxane',
        'Amodimethicone',
        'Phenyl Trimethicone',
        'Диметикон',
      ]) {
        expect(IngredientMatcher.inGroup(n, 'silicone'), isTrue, reason: n);
      }
      expect(IngredientMatcher.inGroup('Glycerin', 'silicone'), isFalse);
    });

    test('mineral oil, formaldehyde releasers, phthalates, triclosan', () {
      expect(
        IngredientMatcher.inGroup('Paraffinum Liquidum', 'mineral_oil'),
        isTrue,
      );
      expect(IngredientMatcher.inGroup('Petrolatum', 'mineral_oil'), isTrue);
      expect(IngredientMatcher.inGroup('Вазелин', 'mineral_oil'), isTrue);
      expect(
        IngredientMatcher.inGroup('DMDM Hydantoin', 'formaldehyde'),
        isTrue,
      );
      expect(
        IngredientMatcher.inGroup('Quaternium-15', 'formaldehyde'),
        isTrue,
      );
      expect(
        IngredientMatcher.inGroup('Dibutyl Phthalate', 'phthalates'),
        isTrue,
      );
      expect(IngredientMatcher.inGroup('Triclosan', 'triclosan'), isTrue);
      expect(IngredientMatcher.inGroup('Aqua', 'triclosan'), isFalse);
    });

    test('unknown group key never matches', () {
      expect(IngredientMatcher.inGroup('Methylparaben', 'nope'), isFalse);
    });
  });

  group('matching with the blacklist', () {
    final blacklist = [
      item('Парабены', group: 'paraben'),
      item('Сульфаты (SLS / SLES)', group: 'sulfate'),
      item('Силиконы', group: 'silicone', enabled: false),
      item('Отдушка', custom: true),
    ];

    test('only enabled items count', () {
      final m = IngredientMatcher.match([
        'Aqua',
        'Dimethicone',
        'Methylparaben',
      ], blacklist);
      expect(m.map((e) => e.item.name), ['Парабены']);
      expect(m.single.ingredient, 'Methylparaben');
      expect(m.single.reason, ScanMatchReason.group);
    });

    test('custom components match by name, case-insensitively', () {
      final m = IngredientMatcher.match([
        'Aqua',
        'ОТДУШКА (Parfum)',
      ], blacklist);
      expect(m.single.item.name, 'Отдушка');
      expect(m.single.reason, ScanMatchReason.custom);
    });

    test(
      'one ingredient can hit several items and one item several ingredients',
      () {
        final m = IngredientMatcher.match([
          'Sodium Lauryl Sulfate',
          'Sodium Laureth Sulfate',
          'Propylparaben',
        ], blacklist);
        expect(m.length, 3);
        expect(m.where((e) => e.item.name.startsWith('Сульфаты')).length, 2);
      },
    );

    test('a clean list and an empty blacklist give no matches', () {
      expect(IngredientMatcher.match(['Aqua', 'Glycerin'], blacklist), isEmpty);
      expect(IngredientMatcher.match(['Methylparaben'], const []), isEmpty);
    });

    test('very short custom names are ignored (no matching every word)', () {
      final m = IngredientMatcher.match(['Aqua'], [item('a', custom: true)]);
      expect(m, isEmpty);
    });
  });
}
