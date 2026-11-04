import 'package:flutter_test/flutter_test.dart';

import 'package:cosmetix/services/ingredient_catalog.dart';
import 'package:cosmetix/services/routine_checks.dart';

/// "Сочетаемость активных ингредиентов": the table the user supplied, copied
/// cell by cell. Each of the 13 ingredients is a row and a column.
///
///   ok   - можно сочетать (green tick)
///   care - сочетать с осторожностью (pink "!"): several acids
///   sep  - лучше разнести по времени или дням (sun and moon)
enum _Cell { ok, care, sep }

const _names = [
  'hyaluronic', // гиалуроновая кислота
  'niacinamide', // ниацинамид
  'retinoid', // ретиноиды
  'bakuchiol', // бакучиол
  'glycolic', // гликолевая кислота
  'lactic', // молочная кислота
  'salicylic', // BHA
  'lha', // LHA
  'pha', // PHA
  'peptide', // пептиды
  'vitamin_c', // витамин C (L-аскорбиновая кислота)
  'vitamin_c_derivative', // производные витамина C
  'probiotic', // бифидобактерии / пробиотические компоненты
];

const _acids = {'glycolic', 'lactic', 'salicylic', 'lha', 'pha'};

/// Every cell that is not green in the table.
_Cell _expected(String a, String b) {
  bool pair(String x, String y) => (a == x && b == y) || (a == y && b == x);
  // acids with each other
  if (_acids.contains(a) && _acids.contains(b)) return _Cell.care;
  // retinoids with every acid and with L-ascorbic acid
  if (a == 'retinoid' || b == 'retinoid') {
    final other = a == 'retinoid' ? b : a;
    if (_acids.contains(other) || other == 'vitamin_c') return _Cell.sep;
  }
  // L-ascorbic acid with every acid
  if (pair('vitamin_c', a) || pair('vitamin_c', b)) {
    final other = a == 'vitamin_c' ? b : a;
    if (_acids.contains(other)) return _Cell.sep;
  }
  return _Cell.ok;
}

RoutineItem _item(String code) => RoutineItem(title: code, actives: {code});

void main() {
  group('the compatibility table, every pair', () {
    for (var i = 0; i < _names.length; i++) {
      for (var j = i + 1; j < _names.length; j++) {
        final a = _names[i], b = _names[j];
        final want = _expected(a, b);
        test('$a + $b: ${want.name}', () {
          final r = ActiveRules.check([_item(a), _item(b)]);
          switch (want) {
            case _Cell.ok:
              expect(r, isEmpty);
            case _Cell.care:
              expect(r.single.text, contains('с осторожностью'));
            case _Cell.sep:
              expect(r.single.text, contains('разнести'));
          }
        });
      }
    }

    test('the table is as big as the picture: 13 x 13', () {
      expect(_names.length, 13);
      final cells = [
        for (var i = 0; i < 13; i++)
          for (var j = i + 1; j < 13; j++) _expected(_names[i], _names[j]),
      ];
      // 78 pairs: 10 acid-acid, 6 retinoid, 6 vitamin C - 5 acids ... counted
      // straight from the picture
      expect(cells.length, 78);
      expect(cells.where((c) => c == _Cell.care).length, 10);
      expect(cells.where((c) => c == _Cell.sep).length, 5 + 1 + 5);
    });
  });

  group('the INCI names reach the right column of the table', () {
    Set<String> of(String inci) => IngredientCatalog.detect(inci);

    test('L-ascorbic acid and its derivatives are different columns', () {
      expect(of('Aqua, Ascorbic Acid'), contains('vitamin_c'));
      expect(
        of('Aqua, Ascorbic Acid'),
        isNot(contains('vitamin_c_derivative')),
      );
      for (final d in [
        'Sodium Ascorbyl Phosphate',
        'Magnesium Ascorbyl Phosphate',
        'Ascorbyl Glucoside',
        '3-O-Ethyl Ascorbic Acid',
        'Ascorbic Acid 2-Glucoside',
      ]) {
        final r = of('Aqua, $d');
        expect(r, contains('vitamin_c_derivative'), reason: d);
        expect(r, isNot(contains('vitamin_c')), reason: d);
      }
    });

    test('LHA is not taken for BHA', () {
      final lha = of('Aqua, Capryloyl Salicylic Acid');
      expect(lha, contains('lha'));
      expect(lha, isNot(contains('salicylic')));
      final bha = of('Aqua, Salicylic Acid');
      expect(bha, contains('salicylic'));
      expect(bha, isNot(contains('lha')));
    });

    test('PHA, lactic and glycolic acids are found', () {
      expect(of('Aqua, Gluconolactone'), contains('pha'));
      expect(of('Aqua, Lactobionic Acid'), contains('pha'));
      expect(of('Aqua, Lactic Acid'), contains('lactic'));
      expect(of('Aqua, Glycolic Acid'), contains('glycolic'));
    });

    test('a product with a derivative of vitamin C is quiet next to acids', () {
      final derivative = RoutineItem(
        title: 'Serum',
        actives: of('Aqua, Sodium Ascorbyl Phosphate'),
      );
      final acid = RoutineItem(
        title: 'Toner',
        actives: of('Aqua, Glycolic Acid'),
      );
      final retinol = RoutineItem(title: 'Night', actives: of('Aqua, Retinol'));
      expect(ActiveRules.check([derivative, acid]), isEmpty);
      expect(ActiveRules.check([derivative, retinol]), isEmpty);
      final lAscorbic = RoutineItem(
        title: 'C',
        actives: of('Aqua, Ascorbic Acid'),
      );
      expect(ActiveRules.check([lAscorbic, acid]), hasLength(1));
    });
  });
}
