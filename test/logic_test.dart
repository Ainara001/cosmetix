import 'package:flutter_test/flutter_test.dart';

import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/models/product_filter.dart';
import 'package:cosmetix/models/safety_models.dart';
import 'package:cosmetix/services/color_test_service.dart';
import 'package:cosmetix/services/ingredient_analyzer.dart';

Product _p(
  int id,
  String name,
  int price, {
  int? old,
  String category = 'Макияж',
  String zone = 'Губы',
  bool stock = true,
}) => Product(
  id: id,
  brand: 'Brand',
  name: name,
  category: category,
  zone: zone,
  price: price,
  oldPrice: old,
  inStock: stock,
  art: 'tube',
  color: 0xFFFFFFFF,
  description: '',
  naturalPercent: 90,
  createdAt: id,
);

void main() {
  final products = [
    _p(1, 'Тинт', 1500, old: 3000),
    _p(2, 'Палетка', 4800, zone: 'Глаза'),
    _p(3, 'Крем', 7000, category: 'Уход за лицом', zone: 'Лицо', stock: false),
  ];

  group('ProductFilter', () {
    test('discount percent', () {
      expect(products[0].discountPercent, 50);
      expect(products[1].hasDiscount, isFalse);
    });

    test('filters by name, zone, status and price', () {
      List<Product> run(ProductFilter f) =>
          ProductFilter.apply(products, f, ProductSort.priceAsc);
      expect(run(const ProductFilter(name: 'палет')).map((p) => p.id), [2]);
      expect(run(const ProductFilter(zone: 'Лицо')).map((p) => p.id), [3]);
      expect(
        run(const ProductFilter(status: ProductStatus.sale)).map((p) => p.id),
        [1],
      );
      expect(
        run(
          const ProductFilter(status: ProductStatus.outOfStock),
        ).map((p) => p.id),
        [3],
      );
      expect(
        run(
          const ProductFilter(minPrice: 2000, maxPrice: 5000),
        ).map((p) => p.id),
        [2],
      );
      expect(run(const ProductFilter(name: 'nothing')), isEmpty);
    });

    test('sorting', () {
      final desc = ProductFilter.apply(
        products,
        const ProductFilter(),
        ProductSort.priceDesc,
      );
      expect(desc.first.id, 3);
      final newest = ProductFilter.apply(
        products,
        const ProductFilter(),
        ProductSort.newest,
      );
      expect(newest.first.id, 3);
    });

    test('copyWith can clear a nullable field', () {
      final f = const ProductFilter(zone: 'Губы').copyWith(zone: null);
      expect(f.zone, isNull);
      expect(f.isDefault, isTrue);
    });
  });

  group('IngredientAnalyzer', () {
    const water = Ingredient(
      id: 1,
      name: 'Вода',
      description: '',
      risk: 0,
      isAllergen: false,
    );
    const salicylic = Ingredient(
      id: 2,
      name: 'Салициловая кислота',
      description: '',
      risk: 1,
      isAllergen: true,
    );
    const paraben = Ingredient(
      id: 3,
      name: 'Парабены',
      description: '',
      risk: 2,
      isAllergen: true,
      groupKey: 'paraben',
    );

    test('score matches the Figma example (8.5)', () {
      final a = IngredientAnalyzer.analyze(const [
        water,
        salicylic,
        paraben,
      ], const []);
      expect(a.score, 8.5);
      expect(a.criticalCount, 1);
      expect(a.allergens.length, 2);
      expect(a.grade, 'A');
    });

    test('blacklist hits by group and by custom name', () {
      const list = [
        BlacklistItem(
          id: 1,
          name: 'Парабены',
          description: '',
          enabled: true,
          isCustom: false,
          groupKey: 'paraben',
        ),
        BlacklistItem(
          id: 2,
          name: 'салицил',
          description: '',
          enabled: true,
          isCustom: true,
        ),
        BlacklistItem(
          id: 3,
          name: 'Силиконы',
          description: '',
          enabled: false,
          isCustom: false,
          groupKey: 'silicone',
        ),
      ];
      final a = IngredientAnalyzer.analyze(const [
        water,
        salicylic,
        paraben,
      ], list);
      expect(a.blacklistHits, containsAll(['Парабены', 'салицил']));
      expect(a.blacklistHits.length, 2);
    });
  });

  group('ColorTestService', () {
    test('warm + light = Весна, cool + light = Лето', () {
      expect(
        ColorTestService.compute(warm: 4, depth: -3, vein: 3).colorType,
        'Весна',
      );
      expect(
        ColorTestService.compute(warm: -4, depth: -3, vein: -3).colorType,
        'Лето',
      );
    });

    test('deep colouring gives Осень / Зима', () {
      expect(
        ColorTestService.compute(warm: 4, depth: 5, vein: 3).colorType,
        'Осень',
      );
      expect(
        ColorTestService.compute(warm: -4, depth: 5, vein: -3).colorType,
        'Зима',
      );
    });
  });
}
