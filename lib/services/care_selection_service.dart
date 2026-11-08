import 'package:cosmetix/core/beauty/beauty_codes.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/services/age_safety.dart';
import 'package:cosmetix/services/ingredient_catalog.dart';

/// One care function (what a product should do) and the active-ingredient
/// groups that deliver it. A "skin need" is translated into a list of these.
class CareFunction {
  const CareFunction(this.label, this.actives);

  /// Russian source label (translated with `tr` when shown).
  final String label;

  /// Codes of `IngredientCatalog` groups (niacinamide, salicylic, ...).
  final Set<String> actives;
}

/// A skin need: skin type + concerns, plus the constraints that restrict which
/// actives are safe for this person. Everything is a plain value so the
/// selection stays deterministic and works with no AI and no network.
class CareNeed {
  const CareNeed({
    this.skinType,
    this.concerns = const {},
    this.age,
    this.pregnant = false,
    this.budget = 0,
  });

  final SkinType? skinType;
  final Set<SkinConcern> concerns;
  final int? age;

  /// True when the user said they are pregnant (or planning). The app stays
  /// conservative: actives that are not recommended during pregnancy are
  /// excluded and the result says "ask a doctor".
  final bool pregnant;

  /// Tenge. 0 = no budget limit.
  final int budget;

  bool get sensitive =>
      skinType == SkinType.sensitive ||
      concerns.contains(SkinConcern.sensitivity);
}

/// One product that fits the need.
class CareMatch {
  const CareMatch({
    required this.product,
    required this.functions,
    required this.matchedActives,
    required this.price,
  });

  final Product product;
  final List<CareFunction> functions;

  /// The target actives this product actually contains.
  final Set<String> matchedActives;

  /// The verified price in tenge (the same as `product.price`).
  final int price;
}

/// Why a product was left out of the selection.
class CareExclusion {
  const CareExclusion(this.product, this.reason);

  final Product product;

  /// Russian source reason (translated with `tr` when shown).
  final String reason;
}

class CareSelectionResult {
  const CareSelectionResult({required this.matches, required this.exclusions});

  final List<CareMatch> matches;
  final List<CareExclusion> exclusions;
}

/// Deterministic "need -> function -> active -> restriction -> product"
/// selection. No AI: the only inputs are the published INCI list and the
/// verified shop price already stored in SQLite.
///
/// Not medical advice: the restriction rules are conservative and cite the
/// same public guidance the rest of the app uses (retinoids are not used in
/// pregnancy; strong acids and alcohol/fragrance may irritate sensitive skin).
class CareSelectionService {
  CareSelectionService._();

  // need -> care functions (and their actives)
  static const Map<SkinConcern, List<CareFunction>> _byConcern = {
    SkinConcern.acne: [
      CareFunction('Противовоспалительное действие', {
        'niacinamide',
        'salicylic',
        'azelaic',
        'zinc',
        'centella',
        'benzoyl',
      }),
      CareFunction('Отшелушивание и очищение пор', {
        'salicylic',
        'glycolic',
        'lactic',
        'lha',
        'mandelic',
        'pha',
      }),
    ],
    SkinConcern.pigmentation: [
      CareFunction('Осветление постакне', {
        'niacinamide',
        'azelaic',
        'tranexamic',
        'vitamin_c',
        'vitamin_c_derivative',
      }),
      CareFunction('Обновление кожи', {
        'glycolic',
        'lactic',
        'mandelic',
        'pha',
        'retinoid',
      }),
    ],
    SkinConcern.dryness: [
      CareFunction('Увлажнение', {
        'hyaluronic',
        'glycerin',
        'panthenol',
        'ceramide',
        'squalane',
        'beta_glucan',
      }),
    ],
    SkinConcern.sensitivity: [
      CareFunction('Успокоение и восстановление барьера', {
        'centella',
        'panthenol',
        'allantoin',
        'beta_glucan',
        'ceramide',
        'ferment',
      }),
    ],
    SkinConcern.aging: [
      CareFunction('Антивозрастной уход', {
        'retinoid',
        'peptide',
        'vitamin_c',
        'ceramide',
        'vitamin_e',
      }),
    ],
  };

  static const Map<SkinType, List<CareFunction>> _bySkinType = {
    SkinType.oily: [
      CareFunction('Контроль жирности', {'niacinamide', 'zinc', 'salicylic'}),
    ],
    SkinType.dry: [
      CareFunction('Восстановление липидов', {
        'ceramide',
        'squalane',
        'glycerin',
      }),
    ],
  };

  // Actives a conservative rule excludes, with the reason (Russian source).
  static const Map<String, String> _pregnancyAvoid = {
    'retinoid': 'При беременности ретиноиды не используют: спросите врача.',
    'salicylic':
        'При беременности салициловую кислоту не предлагаем: спросите врача.',
    'lha': 'При беременности LHA не предлагаем: спросите врача.',
    'benzoyl':
        'При беременности бензоилпероксид не предлагаем: спросите врача.',
  };

  static const Map<String, String> _sensitiveAvoid = {
    'glycolic': 'Гликолевая кислота может раздражать чувствительную кожу.',
    'salicylic': 'Салициловая кислота может раздражать чувствительную кожу.',
    'lha': 'LHA может раздражать чувствительную кожу.',
    'pha': 'PHA может раздражать чувствительную кожу.',
    'mandelic': 'Миндальная кислота может раздражать чувствительную кожу.',
    'retinoid': 'Ретиноиды могут раздражать чувствительную кожу.',
    'benzoyl': 'Бензоилпероксид может раздражать чувствительную кожу.',
    'vitamin_c': 'Чистый витамин C может пощипывать чувствительную кожу.',
    'alcohol': 'Спирт может раздражать чувствительную кожу.',
    'fragrance': 'Отдушка может раздражать чувствительную кожу.',
  };

  /// Every care function that applies to this need, in a stable order.
  static List<CareFunction> functionsOf(CareNeed need) {
    final f = <CareFunction>[];
    if (need.skinType != null) {
      f.addAll(_bySkinType[need.skinType] ?? const <CareFunction>[]);
    }
    for (final c in need.concerns) {
      f.addAll(_byConcern[c] ?? const <CareFunction>[]);
    }
    return f;
  }

  /// The actives a product must contain to be considered (union of the
  /// functions). A product with none of these is not relevant.
  static Set<String> targetActives(CareNeed need) => {
    for (final f in functionsOf(need)) ...f.actives,
  };

  /// Active -> reason it is avoided for this person (empty when none).
  static Map<String, String> avoidReasons(CareNeed need) {
    final m = <String, String>{};
    if (need.pregnant) m.addAll(_pregnancyAvoid);
    if (need.sensitive) m.addAll(_sensitiveAvoid);
    return m;
  }

  /// Selects and ranks the products. Only products with a verified price
  /// (`Product.hasPrice`) and within [CareNeed.budget] are considered; the
  /// rest are reported as exclusions.
  static CareSelectionResult select(CareNeed need, Iterable<Product> products) {
    final target = targetActives(need);
    final avoid = avoidReasons(need);
    final functions = functionsOf(need);

    final matches = <CareMatch>[];
    final exclusions = <CareExclusion>[];

    for (final p in products) {
      if (!p.hasPrice) {
        exclusions.add(CareExclusion(p, 'Нет проверенной цены'));
        continue;
      }
      if (need.budget > 0 && p.price > need.budget) {
        exclusions.add(CareExclusion(p, 'Дороже бюджета'));
        continue;
      }
      final actives = IngredientCatalog.of(p);
      if (AgeSafety.blocks(need.age, actives)) {
        exclusions.add(CareExclusion(p, 'Не подходит по возрасту'));
        continue;
      }
      final blocked = avoid.keys.toSet().intersection(actives);
      if (blocked.isNotEmpty) {
        exclusions.add(CareExclusion(p, avoid[blocked.first]!));
        continue;
      }
      final matched = target.intersection(actives);
      if (matched.isEmpty) {
        exclusions.add(CareExclusion(p, 'Нет подходящих активов'));
        continue;
      }
      matches.add(
        CareMatch(
          product: p,
          functions: [
            for (final f in functions)
              if (f.actives.any(matched.contains)) f,
          ],
          matchedActives: matched,
          price: p.price,
        ),
      );
    }

    matches.sort((a, b) {
      final byScore = b.matchedActives.length.compareTo(
        a.matchedActives.length,
      );
      if (byScore != 0) return byScore;
      return a.price.compareTo(b.price);
    });
    return CareSelectionResult(matches: matches, exclusions: exclusions);
  }
}
