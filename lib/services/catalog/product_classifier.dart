import 'package:cosmetix/services/ingredient_catalog.dart';

/// The form of a product: what it is, independent of what it is for.
enum ProductForm {
  cream,
  gel,
  serum,
  toner,
  essence,
  ampoule,
  lotion,
  cleanser,
  micellar,
  cleansingOil,
  mask,
  sunscreen,
  peeling,
  lipCare,
  shampoo,
  makeup,
  perfume,
  giftSet,
}

/// What a product is mainly for. A product can have several purposes but the
/// main one is the first of [ProductClass.purposes].
enum Purpose {
  cleansing,
  hydration,
  barrierRepair,
  acneCare,
  exfoliation,
  sunProtection,
  rednessCare,
  brightening,
  soothing,
  oilControl,
}

/// One active ingredient group found in the INCI list and how high it stands in
/// it (1 = first). INCI lists are sorted by amount, so a high rank means a
/// meaningful amount and a low one means a trace.
class ActiveHit {
  const ActiveHit(this.code, this.rank);

  final String code;
  final int rank;

  @override
  String toString() => '$code@$rank';
}

/// The result of classifying one product. Nothing here is a guess: [form] and
/// [purposes] are null / empty when the name and the INCI list do not support
/// them, and then [needsReview] is true (the product waits for a person).
class ProductClass {
  const ProductClass({
    required this.form,
    required this.rinseOff,
    required this.purposes,
    required this.actives,
    required this.evidence,
    required this.needsReview,
    required this.reviewReasons,
  });

  /// Null when it cannot be told.
  final ProductForm? form;

  /// Washed off after use (cleanser, shampoo): such a product is never a
  /// leave-on cream. Null when unknown.
  final bool? rinseOff;
  final List<Purpose> purposes;
  final List<ActiveHit> actives;

  /// Why each decision was made ("name: cleanser", "INCI: salicylic@3").
  final List<String> evidence;
  final bool needsReview;
  final List<String> reviewReasons;

  Purpose? get mainPurpose => purposes.isEmpty ? null : purposes.first;
}

/// Classifies a skincare product by its form, purpose and active ingredients,
/// separately. Reads the NAME, the CATEGORY and the INCI list together; never
/// the name or the shop category alone.
///
/// A rule based on the position of an ingredient in the INCI list is a
/// heuristic: a list is sorted by amount, but the real percentage is not
/// published. Anything the rules cannot decide goes to manual review.
class ProductClassifier {
  const ProductClassifier();

  /// An acid or an active counts as "the point of the product" only when it is
  /// among the first ingredients.
  static const meaningfulRank = 10;

  /// Most specific first.
  static const _priority = [
    Purpose.cleansing,
    Purpose.sunProtection,
    Purpose.exfoliation,
    Purpose.acneCare,
    Purpose.brightening,
    Purpose.oilControl,
    Purpose.barrierRepair,
    Purpose.soothing,
    Purpose.hydration,
    Purpose.rednessCare,
  ];

  static final _word = RegExp(r'[a-zа-яё0-9]+', caseSensitive: false);

  static Set<String> _tokens(String text) => {
    for (final m in _word.allMatches(text.toLowerCase())) m.group(0)!,
  };

  ProductClass classify({
    required String name,
    required String category,
    required String inci,
    String zone = '',
  }) {
    final evidence = <String>[];
    final reasons = <String>[];
    final t = _tokens(name);
    bool has(Iterable<String> any) => any.any(t.contains);

    // ---------------------------------------------------------------- form
    ProductForm? form;
    bool? rinseOff;
    void pick(ProductForm f, String why, {bool? rinse}) {
      form = f;
      rinseOff = rinse ?? rinseOff;
      evidence.add('name: $why');
    }

    final isMakeup = category == 'Макияж';
    if (category == 'Подарки' || has(const ['набор', 'set'])) {
      pick(ProductForm.giftSet, 'gift set');
    } else if (category == 'Парфюмерия') {
      pick(ProductForm.perfume, 'perfume category');
    } else if (isMakeup) {
      pick(ProductForm.makeup, 'makeup category');
    } else if (has(const ['shampoo', 'шампунь'])) {
      // "Serum Shampoo" is a shampoo: the washing word wins over "serum"
      pick(ProductForm.shampoo, 'shampoo', rinse: true);
    } else if (has(const ['shower', 'душа', 'душ']) ||
        (has(const ['body', 'тела']) && has(const ['wash', 'мытья']))) {
      // "Shower Gel", "Cream-Oil Shower", "Body Wash": washed off the body,
      // not a leave-on gel or cream (found on the Open Beauty Facts sample)
      pick(ProductForm.cleanser, 'shower / body wash', rinse: true);
    } else if (has(const ['micellar', 'мицеллярная', 'мицеллярка'])) {
      pick(ProductForm.micellar, 'micellar water', rinse: false);
    } else if (has(const [
          'cleanser',
          'cleansing',
          'foam',
          'wash',
          'умывания',
          'пенка',
          'очищающий',
        ]) &&
        !has(const ['oil', 'масло'])) {
      // "Gel Cleanser" is a cleanser (rinsed off), not a gel
      pick(ProductForm.cleanser, 'cleanser', rinse: true);
    } else if (has(const ['oil', 'масло']) &&
        has(const ['cleansing', 'cleanser', 'очищающее'])) {
      pick(ProductForm.cleansingOil, 'cleansing oil', rinse: true);
    } else if (has(const ['lip', 'губ', 'губы']) &&
        has(const ['mask', 'balm', 'бальзам', 'маска'])) {
      pick(ProductForm.lipCare, 'lip mask / balm', rinse: false);
    } else if (has(const [
      'spf',
      'sunscreen',
      'sun',
      'санскрин',
      'солнцезащитный',
    ])) {
      pick(ProductForm.sunscreen, 'SPF', rinse: false);
    } else if (has(const ['peel', 'peeling', 'exfoliant', 'пилинг'])) {
      pick(ProductForm.peeling, 'peeling', rinse: false);
    } else if (has(const ['toner', 'toning', 'тонер', 'тоник'])) {
      pick(ProductForm.toner, 'toner', rinse: false);
    } else if (has(const ['essence', 'эссенция'])) {
      pick(ProductForm.essence, 'essence', rinse: false);
    } else if (has(const ['ampoule', 'ампула'])) {
      pick(ProductForm.ampoule, 'ampoule', rinse: false);
    } else if (has(const ['serum', 'сыворотка', 'drop'])) {
      pick(ProductForm.serum, 'serum', rinse: false);
    } else if (has(const ['mask', 'маска'])) {
      pick(ProductForm.mask, 'mask');
    } else if (has(const ['lotion', 'лосьон', 'emulsion', 'эмульсия'])) {
      pick(ProductForm.lotion, 'lotion', rinse: false);
    } else if (has(const ['cream', 'creme', 'крем'])) {
      pick(ProductForm.cream, 'cream', rinse: false);
    } else if (has(const ['gel', 'гель'])) {
      pick(ProductForm.gel, 'gel', rinse: false);
    }

    // The INCI list can tell a peeling when the name does not ("... Power
    // Liquid"): an acid exfoliant at the top of the list, leave-on liquid.
    final ranked = _ranked(
      inci,
      isMakeup: isMakeup || category == 'Парфюмерия',
    );
    int? rankOf(String code) {
      for (final h in ranked) {
        if (h.code == code) return h.rank;
      }
      return null;
    }

    bool top(String code, [int limit = meaningfulRank]) =>
        (rankOf(code) ?? 999) <= limit;
    final exfoliatingAcid = [
      'glycolic',
      'lactic',
      'salicylic',
      'mandelic',
      'lha',
      'pha',
    ].where(top).toList();

    if (form == null &&
        !isMakeup &&
        exfoliatingAcid.isNotEmpty &&
        has(const ['liquid', 'solution', 'acid'])) {
      pick(
        ProductForm.peeling,
        'liquid with an acid at the top of the INCI (${exfoliatingAcid.join(', ')})',
        rinse: false,
      );
      reasons.add('form inferred from the INCI list: check the product page');
    }
    if (form == null) {
      reasons.add('the name does not say what the product is');
    }

    // ------------------------------------------------------------- purposes
    final purposes = <Purpose>[];
    void add(Purpose p, String why) {
      if (!purposes.contains(p)) {
        purposes.add(p);
        evidence.add('purpose ${p.name}: $why');
      }
    }

    if (!isMakeup && category != 'Парфюмерия' && form != ProductForm.shampoo) {
      if (form == ProductForm.cleanser ||
          form == ProductForm.micellar ||
          form == ProductForm.cleansingOil) {
        add(Purpose.cleansing, 'cleansing form');
      }
      if (form == ProductForm.sunscreen) {
        add(Purpose.sunProtection, 'SPF in the name');
      }
      if (exfoliatingAcid.isNotEmpty && form != ProductForm.cleanser) {
        add(
          Purpose.exfoliation,
          'acid at the top of the INCI: ${exfoliatingAcid.map((c) => '$c@${rankOf(c)}').join(', ')}',
        );
      }
      if (top('salicylic') || top('azelaic') || top('benzoyl')) {
        add(
          Purpose.acneCare,
          'BHA / azelaic acid / benzoyl peroxide at the top of the INCI',
        );
      }
      if (top('ceramide', 12) || has(const ['ceramidin', 'barrier'])) {
        add(Purpose.barrierRepair, 'ceramides (INCI) or barrier in the name');
      }
      if (form != ProductForm.cleanser &&
          form != ProductForm.sunscreen &&
          (top('hyaluronic', 12) ||
              top('glycerin', 6) ||
              top('panthenol', 12) ||
              top('beta_glucan', 12))) {
        add(Purpose.hydration, 'humectants at the top of the INCI');
      }
      if (top('niacinamide') && top('zinc', 12)) {
        add(Purpose.oilControl, 'niacinamide with zinc at the top of the INCI');
      }
      if (top('centella', 12) ||
          top('allantoin', 12) ||
          top('houttuynia', 12) ||
          has(const ['soothing', 'cica', 'centella', 'heartleaf'])) {
        add(Purpose.soothing, 'calming ingredients / name');
      }
      if (top('vitamin_c', 12) ||
          top('vitamin_c_derivative', 12) ||
          top('tranexamic', 12) ||
          top('azelaic', 12)) {
        add(
          Purpose.brightening,
          'vitamin C / tranexamic / azelaic acid at the top of the INCI',
        );
      }
    }
    if (!isMakeup &&
        category != 'Парфюмерия' &&
        purposes.isEmpty &&
        form != ProductForm.shampoo &&
        form != ProductForm.giftSet) {
      reasons.add('no purpose is supported by the name and the INCI list');
    }

    // the main purpose is the most specific one: an active-driven purpose before
    // the generic hydration
    purposes.sort(
      (a, b) => _priority.indexOf(a).compareTo(_priority.indexOf(b)),
    );

    // a lip product with titanium dioxide is not "sun protection": the UV
    // filter group is only meaningful for a product that claims SPF
    final actives = [
      for (final h in ranked)
        if (!(h.code == 'uv_filter' && form != ProductForm.sunscreen)) h,
    ];

    final needsReview =
        reasons.isNotEmpty &&
            !(form == ProductForm.makeup ||
                form == ProductForm.perfume ||
                form == ProductForm.giftSet ||
                form == ProductForm.shampoo) ||
        form == null;
    return ProductClass(
      form: form,
      rinseOff: rinseOff,
      purposes: purposes,
      actives: actives,
      evidence: evidence,
      needsReview: needsReview,
      reviewReasons: reasons,
    );
  }

  /// The active groups of an INCI list with the position of the first
  /// ingredient that matches (1-based).
  static List<ActiveHit> _ranked(String inci, {required bool isMakeup}) {
    final names = [
      for (final t in inci.split(RegExp(r'\s*,\s*')))
        if (t.trim().isNotEmpty) t.trim().toLowerCase(),
    ];
    final out = <ActiveHit>[];
    for (final g in IngredientCatalog.groups) {
      if (g.kind == IngredientKind.avoid) continue;
      if (isMakeup && g.code == 'uv_filter') continue;
      for (var i = 0; i < names.length; i++) {
        if (g.pattern.hasMatch(names[i])) {
          out.add(ActiveHit(g.code, i + 1));
          break;
        }
      }
    }
    return out;
  }
}
