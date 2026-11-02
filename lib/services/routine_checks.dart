import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/models/care_models.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/services/ingredient_catalog.dart';

/// How serious a finding is.
enum IssueSeverity {
  /// Do not use together.
  avoid,

  /// Possible, but with care (other time of day, other days, a test first).
  caution,
}

/// What the formula of a product is based on (decides what it layers well
/// with). Read from the first ingredients of the INCI list, which are sorted
/// by amount.
enum FormulaBase {
  water('на воде'),
  silicone('на силиконах'),
  oil('на маслах'),
  unknown('');

  const FormulaBase(this.label);

  /// Russian source label (translated with `tr`).
  final String label;
}

/// One thing the app noticed about a set of products.
class RoutineIssue {
  const RoutineIssue(this.severity, this.template, this.args);

  final IssueSeverity severity;

  /// Russian source text with `{name}` placeholders (translated with `trf`).
  final String template;
  final Map<String, Object?> args;

  String get text => trf(template, args);

  @override
  String toString() => '$severity: $text';
}

/// A product as the checks see it: its title, the active groups, the formula
/// base and what kind of product it is.
class RoutineItem {
  const RoutineItem({
    required this.title,
    this.actives = const {},
    this.base = FormulaBase.unknown,
    this.isFoundation = false,
    this.isSkincare = true,
    this.productId,
  });

  final String title;

  /// Codes of `IngredientGroup` (retinoid, vitamin_c, glycolic, ...).
  final Set<String> actives;
  final FormulaBase base;

  /// A foundation, cushion or BB cream: the base of the makeup.
  final bool isFoundation;

  /// A care product that goes on the face before makeup (not makeup, perfume
  /// or hair care).
  final bool isSkincare;
  final int? productId;

  /// From a catalog product: its published INCI list tells everything.
  factory RoutineItem.fromProduct(Product p) {
    final makeup = p.category == 'Макияж';
    return RoutineItem(
      title: '${p.brand} ${tr(p.name)}'.trim(),
      actives: IngredientCatalog.of(p),
      base: FormulaAnalyzer.baseOf(p.inci),
      isFoundation: p.isBaseMakeup,
      isSkincare:
          !makeup && p.category != 'Парфюмерия' && p.category != 'Волосы',
      productId: p.id,
    );
  }

  /// From an entry of the cosmetic bag: the catalog product when it was
  /// picked from there, otherwise what the typed name says.
  factory RoutineItem.fromBag(MyProduct m, Product? catalog) {
    if (catalog != null) {
      final p = RoutineItem.fromProduct(catalog);
      return RoutineItem(
        title: m.title,
        actives: p.actives,
        base: p.base,
        isFoundation: p.isFoundation,
        isSkincare: p.isSkincare,
        productId: m.productId,
      );
    }
    final text = '${m.name} ${m.brand} ${m.notes}';
    final foundation = FormulaAnalyzer.isFoundationText(text);
    final makeup = m.category == 'Макияж';
    return RoutineItem(
      title: m.title,
      actives: IngredientCatalog.detectInText(text),
      isFoundation: foundation,
      isSkincare:
          !foundation &&
          !makeup &&
          m.category != 'Парфюмерия' &&
          m.category != 'Волосы',
    );
  }
}

/// Reads the formula base from an INCI list.
class FormulaAnalyzer {
  FormulaAnalyzer._();

  static final _silicone = RegExp(
    r'dimethicone|siloxane|siloxy|methicone|silicone|dimethiconol|silsesquioxane',
  );
  static final _heavyOil = RegExp(
    r'mineral oil|petrolatum|paraffin|lanolin|butter|polyisobutene',
  );
  static final _oil = RegExp(
    r'\boil\b|butter|petrolatum|paraffin|mineral|polyisobutene|isododecane|'
    r'isohexadecane|palmitate|triglyceride|myristate|malate|dilinoleate|'
    r'squalane|lanolin|\bwax\b',
  );
  static final _foundation = RegExp(
    r'кушон|тональн|foundation|cushion|\bbb\b|\bcc\b|тональник|основа под макияж',
    caseSensitive: false,
  );

  /// How many of the first ingredients are looked at.
  static const head = 8;

  static bool isFoundationText(String text) => _foundation.hasMatch(text);

  /// - two or more silicones among the first ingredients: a silicone formula
  ///   (a cushion or foundation is often "water first" and still a silicone
  ///   emulsion);
  /// - two heavy oils (mineral oil, petrolatum, lanolin, butters) or three
  ///   oils/esters among the first ones: an oil-rich formula (rich cream,
  ///   balm);
  /// - water first: a water-based formula;
  /// - otherwise unknown.
  static FormulaBase baseOf(String inci) {
    if (inci.trim().isEmpty) return FormulaBase.unknown;
    final tokens = [
      for (final t in inci.toLowerCase().split(RegExp(r'\s*,\s*')))
        if (t.trim().isNotEmpty) t.trim(),
    ].take(head).toList();
    final si = tokens.where(_silicone.hasMatch).length;
    final oils = tokens.where(_oil.hasMatch).length;
    final heavy = tokens.where(_heavyOil.hasMatch).length;
    final waterFirst =
        tokens.first.startsWith('water') || tokens.first.startsWith('aqua');
    if (si >= 2) return FormulaBase.silicone;
    if (heavy >= 2 || oils >= 3 || (!waterFirst && oils >= 2)) {
      return FormulaBase.oil;
    }
    if (waterFirst) return FormulaBase.water;
    return FormulaBase.unknown;
  }
}

class _Rule {
  const _Rule(this.a, this.b, this.severity, this.template);

  final Set<String> a;
  final Set<String> b;
  final IssueSeverity severity;
  final String template;
}

/// Combinations of active ingredients that irritate or cancel each other.
/// Not medical advice: these are the rules of thumb dermatologists and
/// ingredient guides repeat.
class ActiveRules {
  ActiveRules._();

  /// AHA / BHA / PHA acids that exfoliate.
  static const acids = {'glycolic', 'lactic', 'mandelic', 'salicylic', 'pha'};

  static const _rules = [
    _Rule(
      {'retinoid'},
      acids,
      IssueSeverity.avoid,
      '«{a}» и «{b}»: ретиноиды и кислоты вместе сильно раздражают кожу, возможны жжение и шелушение. Используйте их в разные вечера.',
    ),
    _Rule(
      {'retinoid'},
      {'benzoyl'},
      IssueSeverity.avoid,
      '«{a}» и «{b}»: бензоилпероксид разрушает ретиноиды и сушит кожу. Разнесите их по времени суток.',
    ),
    _Rule(
      {'retinoid'},
      {'vitamin_c'},
      IssueSeverity.caution,
      '«{a}» и «{b}»: ретинол и витамин C лучше разделить: витамин C утром, ретинол вечером.',
    ),
    _Rule(
      {'vitamin_c'},
      acids,
      IssueSeverity.caution,
      '«{a}» и «{b}»: витамин C вместе с кислотами может жечь кожу. Используйте в разное время или в разные дни.',
    ),
    _Rule(
      {'benzoyl'},
      {'vitamin_c'},
      IssueSeverity.caution,
      '«{a}» и «{b}»: бензоилпероксид окисляет витамин C и снижает его действие. Используйте в разное время.',
    ),
    _Rule(
      acids,
      acids,
      IssueSeverity.caution,
      '«{a}» и «{b}»: две кислоты сразу могут пересушить кожу и ослабить её барьер. Начните с одной.',
    ),
    _Rule(
      {'retinoid'},
      {'retinoid'},
      IssueSeverity.caution,
      '«{a}» и «{b}»: два средства с ретиноидами дают двойную дозу. Достаточно одного.',
    ),
  ];

  /// Conflicts between every pair of [items] (the strongest one per pair).
  static List<RoutineIssue> check(List<RoutineItem> items) {
    final out = <RoutineIssue>[];
    for (var i = 0; i < items.length; i++) {
      for (var j = i + 1; j < items.length; j++) {
        final x = items[i], y = items[j];
        // the same product twice is not a conflict
        if (x.productId != null && x.productId == y.productId) continue;
        _Rule? best;
        for (final r in _rules) {
          final hit =
              _both(x.actives, y.actives, r) || _both(y.actives, x.actives, r);
          if (!hit) continue;
          // two different acids; or the same single acid twice is just a
          // duplicate, not a conflict
          if (r.a == acids && r.b == acids && !_differentAcids(x, y)) continue;
          if (best == null || r.severity.index < best.severity.index) best = r;
        }
        if (best != null) {
          out.add(
            RoutineIssue(best.severity, best.template, {
              'a': x.title,
              'b': y.title,
            }),
          );
        }
      }
    }
    return out;
  }

  static bool _both(Set<String> left, Set<String> right, _Rule r) =>
      left.any(r.a.contains) && right.any(r.b.contains);

  static bool _differentAcids(RoutineItem x, RoutineItem y) {
    final ax = x.actives.intersection(acids);
    final ay = y.actives.intersection(acids);
    return ax.isNotEmpty && ay.isNotEmpty && ax.union(ay).length > 1;
  }

  /// Actives that can irritate: worth a test on a small area first.
  static const irritants = {...acids, 'retinoid', 'vitamin_c', 'benzoyl'};
}

/// What layers badly under a foundation.
class MakeupCompatibility {
  MakeupCompatibility._();

  /// Foundation [over] on top of care product [under].
  static RoutineIssue? check(RoutineItem under, RoutineItem over) {
    if (!over.isFoundation || !under.isSkincare) return null;
    final u = under.base, f = over.base;
    if (u == FormulaBase.unknown || f == FormulaBase.unknown) return null;
    if (f == FormulaBase.silicone && u == FormulaBase.oil) {
      return RoutineIssue(
        IssueSeverity.caution,
        '«{u}» на маслах под «{f}» на силиконах: тон может скользить и плохо держаться. Подождите 10 минут и промокните лишнее салфеткой.',
        {'u': under.title, 'f': over.title},
      );
    }
    if (f == FormulaBase.water && u == FormulaBase.silicone) {
      return RoutineIssue(
        IssueSeverity.caution,
        '«{u}» на силиконах под «{f}» на воде: основа может скатываться и ложиться пятнами. Лучше крем на водной основе или основа на силиконах.',
        {'u': under.title, 'f': over.title},
      );
    }
    if (f == FormulaBase.water && u == FormulaBase.oil) {
      return RoutineIssue(
        IssueSeverity.caution,
        '«{u}» на маслах под «{f}» на воде: тон ложится неровно, возможны полосы. Дайте крему полностью впитаться.',
        {'u': under.title, 'f': over.title},
      );
    }
    return null;
  }

  /// Care products of [items] that sit under a foundation of [items]. With
  /// [ordered] true only the products BEFORE the foundation count (a plan);
  /// otherwise every care product does (a bag, a cart).
  static List<RoutineIssue> checkAll(
    List<RoutineItem> items, {
    bool ordered = false,
  }) {
    final out = <RoutineIssue>[];
    for (var k = 0; k < items.length; k++) {
      final over = items[k];
      if (!over.isFoundation) continue;
      for (var i = 0; i < items.length; i++) {
        if (i == k || (ordered && i > k)) continue;
        final issue = check(items[i], over);
        if (issue != null) out.add(issue);
      }
    }
    return out;
  }
}

/// A patch test before buying a whole line, and before an active product.
class PatchTestAdvice {
  PatchTestAdvice._();

  /// Care products from this many at once count as "a whole line".
  static const lineSize = 3;

  /// [sensitive] is a sensitive skin type or a concern about redness.
  static List<RoutineIssue> forItems(
    List<RoutineItem> items, {
    required bool sensitive,
  }) {
    if (!sensitive) return const [];
    final care = items.where((i) => i.isSkincare).toList();
    final out = <RoutineIssue>[];
    if (care.length >= lineSize) {
      out.add(
        RoutineIssue(
          IssueSeverity.caution,
          'Сразу {n} средств для ухода при чувствительной коже: если одно не подойдёт, реакцию трудно связать с конкретным. Начните с базового крема, 3–4 дня пробуйте его на небольшом участке кожи (за ухом или на запястье), остальное добавляйте по одному.',
          {'n': care.length},
        ),
      );
    }
    for (final i in care) {
      if (i.actives.any(ActiveRules.irritants.contains)) {
        out.add(
          RoutineIssue(
            IssueSeverity.caution,
            '«{a}» содержит активные компоненты: при чувствительной коже сначала нанесите на небольшой участок на 3–4 дня.',
            {'a': i.title},
          ),
        );
      }
    }
    return out;
  }
}
