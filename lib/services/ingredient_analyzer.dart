import 'package:cosmetix/models/safety_models.dart';

/// Pure logic: compares a product composition with the user's blacklist.
class IngredientAnalyzer {
  IngredientAnalyzer._();

  static IngredientAnalysis analyze(
    List<Ingredient> ingredients,
    List<BlacklistItem> blacklist,
  ) {
    final hits = <String>{};
    for (final b in blacklist.where((b) => b.enabled)) {
      for (final i in ingredients) {
        final sameGroup = b.groupKey != null && b.groupKey == i.groupKey;
        final byName =
            b.isCustom &&
            i.name.toLowerCase().contains(b.name.trim().toLowerCase());
        if (sameGroup || byName) hits.add(b.name);
      }
    }
    return IngredientAnalysis(
      ingredients: ingredients,
      blacklistHits: hits.toList(),
    );
  }
}
