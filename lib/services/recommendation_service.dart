import 'package:cosmetix/core/beauty/beauty_codes.dart';
import 'package:cosmetix/models/beauty_profile.dart';
import 'package:cosmetix/models/care_models.dart';
import 'package:cosmetix/models/reaction_insights.dart';
import 'package:cosmetix/repositories/care_repository.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/models/recommendation.dart';
import 'package:cosmetix/models/safety_models.dart';
import 'package:cosmetix/repositories/product_repository.dart';
import 'package:cosmetix/repositories/safety_repository.dart';
import 'package:cosmetix/repositories/user_repository.dart';
import 'package:cosmetix/services/ingredient_analyzer.dart';

/// Everything needed to personalize the catalog for one user.
class PersonalizationContext {
  const PersonalizationContext({
    required this.profile,
    required this.blacklist,
    required this.candidates,
    this.history = const PersonalHistory.empty(),
  });

  const PersonalizationContext.empty()
    : profile = const BeautyProfile(),
      blacklist = const [],
      candidates = const [],
      history = const PersonalHistory.empty();

  final BeautyProfile profile;
  final List<BlacklistItem> blacklist;
  final List<ProductCandidate> candidates;

  /// Reactions and cosmetic bag, empty unless the user allowed using them.
  final PersonalHistory history;
}

/// Deterministic personalized ranking. No AI here: AI traits stored in SQLite
/// by the classifier are just more input, and the optional AI re-ranking
/// (see AiRecommendationRefiner) can only reorder what this service returns.
///
/// Pipeline: blacklist exclusion (hard) -> compatibility score -> sorting.
class RecommendationService {
  RecommendationService(
    this._products,
    this._safety,
    this._users, [
    this._care,
  ]);

  final ProductRepository _products;
  final SafetyRepository _safety;
  final UserRepository _users;
  final CareRepository? _care;

  Future<PersonalizationContext> loadContext(int userId) async {
    final user = await _users.getById(userId);
    return PersonalizationContext(
      profile: user?.beautyProfile ?? const BeautyProfile(),
      blacklist: await _safety.blacklist(userId),
      candidates: await _products.candidates(userId),
      // history is used only when the user agreed to it
      history: (user?.recoUseHistory ?? false)
          ? await _loadHistory(userId)
          : const PersonalHistory.empty(),
    );
  }

  Future<PersonalHistory> _loadHistory(int userId) async {
    final reactions = await _safety.reactions(userId);
    final reacted = <int, int>{};
    for (final r in reactions) {
      if (r.severity > (reacted[r.productId] ?? 0)) {
        reacted[r.productId] = r.severity;
      }
    }
    final ingredients = <int, List<Ingredient>>{
      for (final id in reacted.keys) id: await _safety.ingredientsOf(id),
    };
    final shared = ReactionInsights.compute(reactions, ingredients);
    final bag = _care == null ? const <MyProduct>[] : await _care.bag(userId);
    return PersonalHistory(
      reactedProducts: reacted,
      ownedProductIds: {
        for (final p in bag)
          if (p.productId != null) p.productId!,
      },
      sharedRiskIngredients: {for (final i in shared.sharedIngredients) i.name},
    );
  }

  // ---- weights (sum of each product kind = 1) ----

  static const _colorWeights = (
    color: 0.35,
    undertone: 0.25,
    skin: 0.15,
    concern: 0.05,
    newness: 0.10,
    stock: 0.10,
  );
  static const _skincareWeights = (
    color: 0.0,
    undertone: 0.0,
    skin: 0.40,
    concern: 0.40,
    newness: 0.10,
    stock: 0.10,
  );

  /// True when an enabled blacklist item matches an ingredient of the product.
  static bool isBlacklisted(
    ProductCandidate c,
    List<BlacklistItem> blacklist,
  ) => IngredientAnalyzer.analyze(
    c.ingredients,
    blacklist,
  ).blacklistHits.isNotEmpty;

  /// Removes blacklisted products, scores the rest and sorts best-first.
  static List<Recommendation> rank({
    required Iterable<ProductCandidate> candidates,
    required BeautyProfile profile,
    required List<BlacklistItem> blacklist,
    PersonalHistory history = const PersonalHistory.empty(),
    DateTime? now,
  }) {
    final allowed = [
      for (final c in candidates)
        if (!isBlacklisted(c, blacklist)) c,
    ];
    final clock = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final result = [
      for (final c in allowed) _score(c, profile, clock, history),
    ];
    result.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return b.product.createdAt.compareTo(a.product.createdAt);
    });
    return result;
  }

  static Recommendation _score(
    ProductCandidate c,
    BeautyProfile profile,
    int nowMs,
    PersonalHistory history,
  ) {
    final reasons = <MatchReason>[];
    final w = c.isColorCosmetic ? _colorWeights : _skincareWeights;

    // color type / undertone: unknown or unspecified -> neutral 0.5
    var color = 0.5;
    if (profile.colorType != null && c.colorTypes.isNotEmpty) {
      if (c.colorTypes.contains(profile.colorType)) {
        color = 1;
        reasons.add(
          MatchReason(MatchReasonType.colorType, profile.colorType!.label),
        );
      } else {
        color = 0;
      }
    }
    var undertone = 0.5;
    if (profile.undertone != null && c.undertones.isNotEmpty) {
      if (c.undertones.contains(profile.undertone)) {
        undertone = 1;
        reasons.add(
          MatchReason(MatchReasonType.undertone, profile.undertone!.label),
        );
      } else {
        undertone = 0;
      }
    }

    // skin type
    var skin = 0.5;
    if (profile.skinType != null && c.skinTypes.isNotEmpty) {
      if (c.skinTypes.contains(profile.skinType)) {
        skin = 1;
        reasons.add(
          MatchReason(MatchReasonType.skinType, profile.skinType!.label),
        );
      } else {
        skin = 0.1;
      }
    }
    skin = _adjustForSensitivity(c, profile, skin, reasons);
    skin = _adjustForTags(c, profile, skin);

    // skin concerns: share of the user's concerns this product addresses
    var concern = 0.5;
    if (profile.concerns.isNotEmpty && c.concerns.isNotEmpty) {
      final hit = profile.concerns.where(c.concerns.contains).toList();
      concern = hit.length / profile.concerns.length;
      for (final h in hit) {
        reasons.add(MatchReason(MatchReasonType.concern, h.label));
      }
    }

    // newness: 1.0 for a product from today, ~0.5 after a month
    final ageDays = ((nowMs - c.product.createdAt) / 86400000).clamp(0, 3650);
    final newness = 1 / (1 + ageDays / 30);
    final stock = c.product.inStock ? 1.0 : 0.0;

    var total =
        w.color * color +
        w.undertone * undertone +
        w.skin * skin +
        w.concern * concern +
        w.newness * newness +
        w.stock * stock;
    total += _adjustForPreferences(c, profile, reasons);
    total += _adjustForHistory(c, history, reasons);
    if (!reasons.any((r) => r.type == MatchReasonType.gentle)) {
      reasons.add(const MatchReason(MatchReasonType.noBlacklist));
    }
    return Recommendation(
      product: c.product,
      score: total.clamp(0.0, 1.0),
      reasons: reasons,
    );
  }

  static bool _hasFragrance(ProductCandidate c) =>
      c.tags.contains('fragrance') ||
      c.ingredients.any(
        (i) => RegExp(
          r'parfum|fragrance|отдушк|парфюм',
          caseSensitive: false,
        ).hasMatch(i.name),
      );

  /// Preferences nudge the score by at most about +-0.1; they never hide a
  /// product.
  static double _adjustForPreferences(
    ProductCandidate c,
    BeautyProfile profile,
    List<MatchReason> reasons,
  ) {
    var adj = 0.0;
    if (profile.preferences.contains(Preferences.fragranceFree)) {
      if (c.tags.contains('fragrance_free') ||
          (!_hasFragrance(c) && c.ingredients.isNotEmpty)) {
        adj += 0.08;
        reasons.add(
          MatchReason(
            MatchReasonType.preference,
            Preferences.label(Preferences.fragranceFree),
          ),
        );
      } else if (_hasFragrance(c)) {
        adj -= 0.10;
      }
    }
    if (profile.preferences.contains(Preferences.natural)) {
      if (c.product.naturalPercent >= 80) {
        adj += 0.06;
        reasons.add(
          MatchReason(
            MatchReasonType.preference,
            Preferences.label(Preferences.natural),
          ),
        );
      } else if (c.product.naturalPercent < 50) {
        adj -= 0.05;
      }
    }
    return adj;
  }

  /// Reactions noted by the user lower the score of that product (up to
  /// -0.32) and of products with the same cautionary ingredient (-0.08).
  /// This is a coincidence-based hint, not a proven cause.
  static double _adjustForHistory(
    ProductCandidate c,
    PersonalHistory history,
    List<MatchReason> reasons,
  ) {
    if (history.isEmpty) return 0;
    var adj = 0.0;
    final severity = history.reactedProducts[c.product.id];
    if (severity != null) {
      adj -= (0.12 + 0.04 * severity).clamp(0.0, 0.32);
      reasons.add(MatchReason(MatchReasonType.previousReaction, '$severity'));
    } else {
      for (final i in c.ingredients) {
        if (history.sharedRiskIngredients.contains(i.name)) {
          adj -= 0.08;
          reasons.add(MatchReason(MatchReasonType.sharedIngredient, i.name));
          break;
        }
      }
    }
    if (history.ownedProductIds.contains(c.product.id)) {
      reasons.add(const MatchReason(MatchReasonType.owned));
    }
    return adj;
  }

  static double _adjustForSensitivity(
    ProductCandidate c,
    BeautyProfile profile,
    double skin,
    List<MatchReason> reasons,
  ) {
    final sensitive =
        profile.skinType == SkinType.sensitive ||
        profile.concerns.contains(SkinConcern.sensitivity);
    if (!sensitive) return skin;
    final irritants = c.ingredients.where((i) => i.isAllergen || i.risk >= 2);
    if (irritants.isEmpty) {
      if (c.ingredients.isNotEmpty) {
        reasons.add(const MatchReason(MatchReasonType.gentle));
        return (skin + 0.15).clamp(0.0, 1.0);
      }
      return skin;
    }
    return (skin - 0.15 * irritants.length).clamp(0.0, 1.0);
  }

  static double _adjustForTags(
    ProductCandidate c,
    BeautyProfile profile,
    double skin,
  ) {
    var v = skin;
    final t = c.tags;
    if (profile.skinType == SkinType.dry && t.contains('hydrating')) {
      v += 0.15;
    }
    if (profile.skinType == SkinType.oily && t.contains('oil_control')) {
      v += 0.15;
    }
    if (profile.skinType == SkinType.sensitive &&
        (t.contains('soothing') || t.contains('fragrance_free'))) {
      v += 0.15;
    }
    if (profile.skinType == SkinType.sensitive && t.contains('fragrance')) {
      v -= 0.25;
    }
    return v.clamp(0.0, 1.0);
  }

  /// Convenience for the catalog: keeps only [products] (a filtered/searched
  /// subset) and returns them personalized.
  static List<Recommendation> rankProducts({
    required Iterable<Product> products,
    required PersonalizationContext context,
    DateTime? now,
  }) {
    final byId = {for (final p in products) p.id: p};
    final ranked = rank(
      candidates: context.candidates.where(
        (c) => byId.containsKey(c.product.id),
      ),
      profile: context.profile,
      blacklist: context.blacklist,
      history: context.history,
      now: now,
    );
    // use the caller's (fresh) product objects, e.g. the favourite flag
    return [
      for (final r in ranked)
        Recommendation(
          product: byId[r.product.id]!,
          score: r.score,
          reasons: r.reasons,
        ),
    ];
  }
}
