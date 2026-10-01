import 'package:flutter/material.dart';

class Ingredient {
  const Ingredient({
    required this.id,
    required this.name,
    required this.description,
    required this.risk,
    required this.isAllergen,
    this.groupKey,
  });

  final int id;
  final String name;
  final String description;

  /// 0 - safe, 1 - caution, 2 - dangerous.
  final int risk;
  final bool isAllergen;
  final String? groupKey;

  factory Ingredient.fromMap(Map<String, Object?> m) => Ingredient(
    id: m['id'] as int,
    name: m['name'] as String,
    description: m['description'] as String? ?? '',
    risk: m['risk'] as int? ?? 0,
    isAllergen: (m['is_allergen'] as int? ?? 0) == 1,
    groupKey: m['group_key'] as String?,
  );
}

class BlacklistItem {
  const BlacklistItem({
    required this.id,
    required this.name,
    required this.description,
    required this.enabled,
    required this.isCustom,
    this.groupKey,
  });

  final int id;
  final String name;
  final String description;
  final bool enabled;
  final bool isCustom;
  final String? groupKey;

  factory BlacklistItem.fromMap(Map<String, Object?> m) => BlacklistItem(
    id: m['id'] as int,
    name: m['name'] as String,
    description: m['description'] as String? ?? '',
    enabled: (m['enabled'] as int? ?? 0) == 1,
    isCustom: (m['is_custom'] as int? ?? 0) == 1,
    groupKey: m['group_key'] as String?,
  );
}

/// Result of analysing a product composition.
class IngredientAnalysis {
  const IngredientAnalysis({
    required this.ingredients,
    required this.blacklistHits,
  });

  final List<Ingredient> ingredients;
  final List<String> blacklistHits;

  /// 10 points, -0.5 for each "caution" and -1 for each "dangerous" ingredient.
  double get score {
    var s = 10.0;
    for (final i in ingredients) {
      if (i.risk == 1) s -= 0.5;
      if (i.risk >= 2) s -= 1.0;
    }
    return s.clamp(0, 10).toDouble();
  }

  int get criticalCount => ingredients.where((i) => i.risk >= 2).length;

  List<Ingredient> get allergens =>
      ingredients.where((i) => i.isAllergen).toList();

  String get grade {
    if (score >= 9) return 'A+';
    if (score >= 8) return 'A';
    if (score >= 6) return 'B';
    return 'C';
  }

  String get headline {
    if (score >= 9) return 'Превосходный состав!';
    if (score >= 7.5) return 'Отличный состав!';
    if (score >= 6) return 'Приемлемый состав';
    return 'Состав вызывает вопросы';
  }

  String get summary {
    if (criticalCount == 0) return 'Критических компонентов не обнаружено.';
    final word = criticalCount == 1
        ? 'критический компонент'
        : 'критических компонента';
    return 'Большинство ингредиентов безопасны. Обнаружен $criticalCount $word.';
  }

  Color get scoreColor => score >= 7.5
      ? const Color(0xFF2E8B63)
      : score >= 6
      ? const Color(0xFFE5A23A)
      : const Color(0xFFD64545);
}

class Reaction {
  const Reaction({
    required this.id,
    required this.productId,
    required this.productName,
    required this.art,
    required this.color,
    required this.title,
    required this.severity,
    required this.date,
    required this.notes,
  });

  final int id;
  final int productId;
  final String productName;
  final String art;
  final int color;
  final String title;
  final int severity;
  final DateTime date;
  final String notes;

  factory Reaction.fromMap(Map<String, Object?> m) => Reaction(
    id: m['id'] as int,
    productId: m['product_id'] as int,
    productName: m['product_name'] as String? ?? 'Удалённый товар',
    art: m['art'] as String? ?? 'bottle',
    color: m['color'] as int? ?? 0xFFF4B6C2,
    title: m['title'] as String,
    severity: m['severity'] as int,
    date: DateTime.fromMillisecondsSinceEpoch(m['reaction_date'] as int),
    notes: m['notes'] as String? ?? '',
  );
}
