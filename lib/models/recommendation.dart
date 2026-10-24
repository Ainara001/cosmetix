import 'package:cosmetix/core/beauty/beauty_codes.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/models/safety_models.dart';

/// A product together with everything the recommendation logic needs.
class ProductCandidate {
  const ProductCandidate({
    required this.product,
    this.skinTypes = const {},
    this.colorTypes = const {},
    this.undertones = const {},
    this.concerns = const {},
    this.tags = const {},
    this.ingredients = const [],
  });

  final Product product;
  final Set<SkinType> skinTypes;
  final Set<ColorType> colorTypes;
  final Set<Undertone> undertones;
  final Set<SkinConcern> concerns;
  final Set<String> tags;
  final List<Ingredient> ingredients;

  /// Decorative cosmetics (lips, eyes, face makeup): color type matters most.
  bool get isColorCosmetic => product.category == 'Макияж';
}

/// Why a product fits (shown on the product page).
enum MatchReasonType {
  colorType,
  undertone,
  skinType,
  concern,
  gentle,
  noBlacklist,

  /// Matches a personal preference (no fragrance, natural composition).
  preference,

  /// The user noted a reaction to this very product (history, with consent).
  previousReaction,

  /// Shares a cautionary ingredient with products that caused reactions.
  sharedIngredient,

  /// The user already has this product in the cosmetic bag.
  owned,
}

/// What the user's own history says (only when they allowed it).
class PersonalHistory {
  const PersonalHistory({
    this.reactedProducts = const {},
    this.ownedProductIds = const {},
    this.sharedRiskIngredients = const {},
  });

  const PersonalHistory.empty() : this();

  /// product id -> highest severity (1..5) noted in the diary.
  final Map<int, int> reactedProducts;

  /// Catalog products in the cosmetic bag.
  final Set<int> ownedProductIds;

  /// Cautionary ingredients found in several products with reactions.
  final Set<String> sharedRiskIngredients;

  bool get isEmpty =>
      reactedProducts.isEmpty &&
      ownedProductIds.isEmpty &&
      sharedRiskIngredients.isEmpty;
}

class MatchReason {
  const MatchReason(this.type, [this.detail]);

  final MatchReasonType type;

  /// Localizable label of the matched profile value (e.g. «Тёплый»).
  final String? detail;
}

class Recommendation {
  const Recommendation({
    required this.product,
    required this.score,
    required this.reasons,
  });

  final Product product;

  /// 0..1
  final double score;
  final List<MatchReason> reasons;

  int get matchPercent => (score * 100).round().clamp(0, 100);
}
