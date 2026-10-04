import 'package:cosmetix/core/beauty/beauty_codes.dart';
import 'package:cosmetix/models/beauty_profile.dart';
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
  });

  const PersonalizationContext.empty()
    : profile = const BeautyProfile(),
      blacklist = const [],
      candidates = const [];

  final BeautyProfile profile;
  final List<BlacklistItem> blacklist;
  final List<ProductCandidate> candidates;
}

/// Deterministic personalized ranking. No AI here: AI traits stored in SQLite
/// by the classifier are just more input, and the optional AI re-ranking
/// (see AiRecommendationRefiner) can only reorder what this service returns.
///
/// Pipeline: blacklist exclusion (hard) -> compatibility score -> sorting.
class RecommendationService {
  RecommendationService(this._products, this._safety, this._users);

  final ProductRepository _products;
  final SafetyRepository _safety;
  final UserRepository _users;

  Future<PersonalizationContext> loadContext(int userId) async {
    final user = await _users.getById(userId);
    return PersonalizationContext(
      profile: user?.beautyProfile ?? const BeautyProfile(),
      blacklist: await _safety.blacklist(userId),
      candidates: await _products.candidates(userId),
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
    DateTime? now,
  }) {
    final allowed = [
      for (final c in candidates)
        if (!isBlacklisted(c, blacklist)) c,
    ];
    final clock = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final result = [for (final c in allowed) _score(c, profile, clock)];
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

    final total =
        w.color * color +
        w.undertone * undertone +
        w.skin * skin +
        w.concern * concern +
        w.newness * newness +
        w.stock * stock;
    if (!reasons.any((r) => r.type == MatchReasonType.gentle)) {
      reasons.add(const MatchReason(MatchReasonType.noBlacklist));
    }
    return Recommendation(
      product: c.product,
      score: total.clamp(0.0, 1.0),
      reasons: reasons,
    );
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
