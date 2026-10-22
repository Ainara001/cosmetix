import 'package:cosmetix/models/safety_models.dart';

/// A product that appears in the diary several times.
class RepeatedProduct {
  const RepeatedProduct({
    required this.productId,
    required this.productName,
    required this.count,
    required this.titles,
    required this.firstDate,
    required this.lastDate,
    required this.averageSeverity,
  });

  final int productId;
  final String productName;
  final int count;

  /// The distinct kinds of reaction that were noted.
  final List<String> titles;
  final DateTime firstDate;
  final DateTime lastDate;
  final double averageSeverity;
}

/// An ingredient present in several products that have diary entries.
class SharedIngredient {
  const SharedIngredient({
    required this.name,
    required this.productCount,
    required this.totalProducts,
  });

  final String name;
  final int productCount;
  final int totalProducts;
}

/// What repeats in the diary. These are observations about the user's own
/// records, not conclusions: a coincidence in time or in composition does not
/// prove that a product or an ingredient caused a reaction.
class ReactionInsights {
  const ReactionInsights({
    required this.repeatedProducts,
    required this.sharedIngredients,
  });

  const ReactionInsights.empty()
    : repeatedProducts = const [],
      sharedIngredients = const [];

  final List<RepeatedProduct> repeatedProducts;
  final List<SharedIngredient> sharedIngredients;

  bool get isEmpty => repeatedProducts.isEmpty && sharedIngredients.isEmpty;

  /// Ingredients with risk 0 (water, glycerin ...) are everywhere and say
  /// nothing, so only cautionary ones and allergens are compared.
  static ReactionInsights compute(
    List<Reaction> reactions,
    Map<int, List<Ingredient>> ingredientsByProduct,
  ) {
    final byProduct = <int, List<Reaction>>{};
    for (final r in reactions) {
      byProduct.putIfAbsent(r.productId, () => []).add(r);
    }

    final repeated = <RepeatedProduct>[];
    for (final e in byProduct.entries) {
      if (e.value.length < 2) continue;
      final dates = e.value.map((r) => r.date).toList()..sort();
      repeated.add(
        RepeatedProduct(
          productId: e.key,
          productName: e.value.first.productName,
          count: e.value.length,
          titles: {for (final r in e.value) r.title}.toList(),
          firstDate: dates.first,
          lastDate: dates.last,
          averageSeverity:
              e.value.fold<int>(0, (s, r) => s + r.severity) / e.value.length,
        ),
      );
    }
    repeated.sort((a, b) => b.count.compareTo(a.count));

    // ingredient -> products (with diary entries) that contain it
    final seen = <String, Set<int>>{};
    for (final id in byProduct.keys) {
      for (final i in ingredientsByProduct[id] ?? const <Ingredient>[]) {
        if (i.risk < 1 && !i.isAllergen) continue;
        seen.putIfAbsent(i.name, () => {}).add(id);
      }
    }
    final total = byProduct.length;
    final shared = <SharedIngredient>[
      if (total >= 2)
        for (final e in seen.entries)
          if (e.value.length >= 2)
            SharedIngredient(
              name: e.key,
              productCount: e.value.length,
              totalProducts: total,
            ),
    ]..sort((a, b) => b.productCount.compareTo(a.productCount));

    return ReactionInsights(
      repeatedProducts: repeated,
      sharedIngredients: shared.take(5).toList(),
    );
  }
}
