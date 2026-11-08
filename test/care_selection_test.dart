import 'package:flutter_test/flutter_test.dart';

import 'package:cosmetix/core/beauty/beauty_codes.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/services/care_selection_service.dart';

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
  group('CareSelectionService', () {
    test(
      'oily + acne + post-acne within a budget selects and ranks by actives',
      () {
        const need = CareNeed(
          skinType: SkinType.oily,
          concerns: {SkinConcern.acne, SkinConcern.pigmentation},
          budget: 10000,
        );

        final products = [
          _p(1, 'Water, Niacinamide, Salicylic Acid', price: 4500),
          _p(2, 'Water, Azelaic Acid, Glycerin', price: 8000),
          _p(3, 'Water, Retinol, Squalane', price: 6000),
          _p(4, 'Water, Butylene Glycol, Carbomer', price: 3000), // no actives
          _p(5, 'Water, Niacinamide, Zinc PCA', price: 12000), // over budget
          _p(6, 'Water, Tranexamic Acid', price: 0), // no verified price
        ];

        final r = CareSelectionService.select(need, products);

        expect(r.matches, isNotEmpty);
        expect(r.matches.every((m) => m.price <= 10000), isTrue);
        expect(r.matches.every((m) => m.matchedActives.isNotEmpty), isTrue);

        // niacinamide + salicylic = 2 matched actives -> ranked first
        expect(r.matches.first.product.id, 1);
        expect(r.matches.first.matchedActives, {'niacinamide', 'salicylic'});

        final ids = r.matches.map((m) => m.product.id).toSet();
        expect(ids, containsAll({1, 2, 3}));

        final excludedIds = r.exclusions.map((e) => e.product.id).toSet();
        expect(excludedIds, containsAll({4, 5, 6}));
        expect(
          r.exclusions.firstWhere((e) => e.product.id == 5).reason,
          'Дороже бюджета',
        );
      },
    );

    test('pregnancy excludes retinoids, salicylic acid, LHA and benzoyl', () {
      const need = CareNeed(
        skinType: SkinType.oily,
        concerns: {SkinConcern.acne},
        pregnant: true,
      );

      final products = [
        _p(1, 'Water, Retinol', price: 5000),
        _p(2, 'Water, Salicylic Acid', price: 5000),
        _p(3, 'Water, Niacinamide, Zinc PCA', price: 5000),
      ];

      final r = CareSelectionService.select(need, products);

      expect(r.matches.map((m) => m.product.id), [3]);
      final excluded = r.exclusions.map((e) => e.product.id).toSet();
      expect(excluded, containsAll({1, 2}));
    });

    test('sensitive skin excludes acids, alcohol and fragrance', () {
      const need = CareNeed(
        skinType: SkinType.sensitive,
        concerns: {SkinConcern.dryness},
      );

      final products = [
        _p(1, 'Water, Glycolic Acid', price: 5000),
        _p(2, 'Water, Salicylic Acid', price: 5000),
        _p(3, 'Water, Glycerin, Parfum', price: 5000), // fragrance
        _p(4, 'Water, Centella Asiatica Extract, Panthenol', price: 5000),
        _p(5, 'Water, Glycerin, Ceramide NP', price: 5000),
      ];

      final r = CareSelectionService.select(need, products);

      final ids = r.matches.map((m) => m.product.id).toSet();
      expect(ids, containsAll({4, 5}));
      expect(
        r.exclusions.map((e) => e.product.id).toSet(),
        containsAll({1, 2, 3}),
      );
    });

    test('a child under 12 is not offered retinoids or benzoyl peroxide', () {
      const need = CareNeed(
        skinType: SkinType.oily,
        concerns: {SkinConcern.acne},
        age: 10,
      );

      final products = [
        _p(1, 'Water, Retinol', price: 5000),
        _p(2, 'Water, Benzoyl Peroxide', price: 5000),
        _p(3, 'Water, Niacinamide', price: 5000),
      ];

      final r = CareSelectionService.select(need, products);

      expect(r.matches.map((m) => m.product.id), [3]);
      expect(
        r.exclusions.map((e) => e.product.id).toSet(),
        containsAll({1, 2}),
      );
    });

    test('budget 0 means no budget limit', () {
      const need = CareNeed(
        skinType: SkinType.dry,
        concerns: {SkinConcern.dryness},
      );

      final products = [
        _p(1, 'Water, Hyaluronic Acid, Glycerin', price: 50000),
      ];

      final r = CareSelectionService.select(need, products);
      expect(r.matches.map((m) => m.product.id), [1]);
    });

    test('functionsOf and targetActives are stable and translatable', () {
      const need = CareNeed(
        skinType: SkinType.oily,
        concerns: {SkinConcern.acne, SkinConcern.pigmentation},
      );

      final functions = CareSelectionService.functionsOf(need);
      expect(functions.map((f) => f.label), contains('Контроль жирности'));
      expect(functions.map((f) => f.label), contains('Осветление постакне'));

      final target = CareSelectionService.targetActives(need);
      expect(target, containsAll({'niacinamide', 'salicylic', 'azelaic'}));
    });
  });
}
