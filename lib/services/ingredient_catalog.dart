import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/services/fragrance_allergens.dart';

/// What a group stands for in the composition filter.
enum IngredientKind {
  /// Acids (hyaluronic, salicylic, ...).
  acid('Кислоты'),

  /// Other active or caring ingredients.
  active('Активные компоненты'),

  /// "Free of ..." choices: the product must NOT contain the group.
  avoid('Без');

  const IngredientKind(this.label);
  final String label;
}

/// One filterable ingredient (or family of ingredients, e.g. every retinoid).
class IngredientGroup {
  const IngredientGroup(
    this.code,
    this.label,
    this.kind,
    this.pattern,
    this.synonyms,
  );

  final String code;

  /// Russian source label (translated with `tr`).
  final String label;
  final IngredientKind kind;

  /// Tested against every INCI name (one comma-separated token at a time).
  final RegExp pattern;

  /// Words a person may type in the search box to find this group.
  final List<String> synonyms;
}

/// The list of ingredients the app can look for in the published INCI text.
/// This is text matching on the INCI list, not a lab analysis: the same
/// product may be formulated differently by shade or market.
class IngredientCatalog {
  IngredientCatalog._();

  static RegExp _re(String p) => RegExp(p, caseSensitive: false);

  static final List<IngredientGroup> groups = [
    // ---- acids ----
    IngredientGroup(
      'hyaluronic',
      'Гиалуроновая кислота',
      IngredientKind.acid,
      _re('hyaluron'),
      const ['гиалурон', 'hyaluron', 'ha'],
    ),
    IngredientGroup(
      'salicylic',
      'Салициловая кислота (BHA)',
      IngredientKind.acid,
      // LHA (capryloyl salicylic acid) is its own group
      _re('^(?!.*capryloyl).*(salicylic acid|betaine salicylate)'),
      const ['салицил', 'salicyl', 'bha'],
    ),
    IngredientGroup(
      'glycolic',
      'Гликолевая кислота (AHA)',
      IngredientKind.acid,
      _re('glycolic acid'),
      const ['гликол', 'glycol', 'aha'],
    ),
    IngredientGroup(
      'lactic',
      'Молочная кислота (AHA)',
      IngredientKind.acid,
      _re(r'^lactic acid'),
      const ['молочн', 'lactic', 'aha'],
    ),
    IngredientGroup(
      'lha',
      'LHA (каприлоил салициловая кислота)',
      IngredientKind.acid,
      _re('capryloyl salicylic'),
      const ['lha', 'каприлоил', 'capryloyl'],
    ),
    IngredientGroup(
      'azelaic',
      'Азелаиновая кислота',
      IngredientKind.acid,
      _re('azelaic'),
      const ['азелаин', 'azelaic'],
    ),
    IngredientGroup(
      'mandelic',
      'Миндальная кислота',
      IngredientKind.acid,
      _re('mandelic'),
      const ['миндал', 'mandelic'],
    ),
    IngredientGroup(
      'vitamin_c',
      'Витамин C (аскорбиновая кислота)',
      IngredientKind.acid,
      // L-ascorbic acid itself; its derivatives are a group of their own
      _re(
        '^(?!.*(ascorbyl|ethyl ascorbic|ascorbate|glucoside)).*ascorbic acid',
      ),
      const ['витамин c', 'витамин с', 'аскорб', 'ascorbic', 'vitamin c'],
    ),
    IngredientGroup(
      'vitamin_c_derivative',
      'Производные витамина C',
      IngredientKind.active,
      _re('ascorbyl|ethyl ascorbic|ascorbate|ascorbic acid 2-glucoside'),
      const ['производные витамина', 'ascorbyl', 'ascorbate'],
    ),
    IngredientGroup(
      'tranexamic',
      'Транексамовая кислота',
      IngredientKind.acid,
      _re('tranexamic'),
      const ['транексам', 'tranexam'],
    ),
    IngredientGroup(
      'pha',
      'PHA (глюконолактон)',
      IngredientKind.acid,
      _re('gluconolactone|lactobionic'),
      const ['pha', 'глюконолактон', 'gluconolactone'],
    ),
    // ---- actives ----
    IngredientGroup(
      'niacinamide',
      'Ниацинамид (B3)',
      IngredientKind.active,
      _re('niacinamide'),
      const ['ниацинамид', 'niacinamide', 'витамин b3', 'b3'],
    ),
    IngredientGroup(
      'retinoid',
      'Ретинол и ретиноиды',
      IngredientKind.active,
      _re('retinol|retinal|retinyl|retinoate|adapalene'),
      const ['ретинол', 'retinol', 'ретиноид', 'retinoid'],
    ),
    IngredientGroup(
      'benzoyl',
      'Бензоилпероксид',
      IngredientKind.active,
      _re('benzoyl peroxide'),
      const ['бензоил', 'бпо', 'benzoyl', 'benzoyl peroxide'],
    ),
    IngredientGroup(
      'panthenol',
      'Пантенол (B5)',
      IngredientKind.active,
      _re('panthenol'),
      const ['пантенол', 'panthenol', 'витамин b5', 'b5'],
    ),
    IngredientGroup(
      'ceramide',
      'Церамиды',
      IngredientKind.active,
      _re('ceramide'),
      const ['церамид', 'ceramide'],
    ),
    IngredientGroup(
      'peptide',
      'Пептиды',
      IngredientKind.active,
      _re('peptide'),
      const ['пептид', 'peptide'],
    ),
    IngredientGroup(
      'centella',
      'Центелла азиатская',
      IngredientKind.active,
      _re('centella|madecassoside|asiaticoside|madecassic|asiatic'),
      const ['центелла', 'centella', 'cica', 'сика'],
    ),
    IngredientGroup(
      'zinc',
      'Цинк',
      IngredientKind.active,
      _re('zinc pca|zinc gluconate|zinc sulfate|zinc picolinate'),
      const ['цинк', 'zinc'],
    ),
    IngredientGroup(
      'squalane',
      'Сквалан',
      IngredientKind.active,
      _re('squalane'),
      const ['сквалан', 'squalane'],
    ),
    IngredientGroup(
      'snail',
      'Муцин улитки',
      IngredientKind.active,
      _re('snail'),
      const ['улитк', 'муцин', 'snail', 'mucin'],
    ),
    IngredientGroup(
      'glycerin',
      'Глицерин',
      IngredientKind.active,
      _re(r'^glycerin$'),
      const ['глицерин', 'glycerin'],
    ),
    IngredientGroup(
      'allantoin',
      'Аллантоин',
      IngredientKind.active,
      _re('allantoin'),
      const ['аллантоин', 'allantoin'],
    ),
    IngredientGroup(
      'beta_glucan',
      'Бета-глюкан',
      IngredientKind.active,
      _re('beta-glucan|betaglucan'),
      const ['глюкан', 'glucan'],
    ),
    IngredientGroup(
      'vitamin_e',
      'Витамин E (токоферол)',
      IngredientKind.active,
      _re('tocopher'),
      const ['витамин e', 'витамин е', 'токоферол', 'tocopher', 'vitamin e'],
    ),
    IngredientGroup(
      'houttuynia',
      'Хауттюйния',
      IngredientKind.active,
      _re('houttuynia'),
      const ['хауттюйн', 'houttuynia'],
    ),
    IngredientGroup(
      'ferment',
      'Ферменты и пробиотики',
      IngredientKind.active,
      _re('ferment|lactobacillus|bifida|saccharomyces'),
      const ['фермент', 'пробиотик', 'ferment', 'probiotic', 'lactobac'],
    ),
    IngredientGroup(
      'uv_filter',
      'УФ-фильтры (SPF)',
      IngredientKind.active,
      _re(
        r'zinc oxide|titanium dioxide|octocrylene|ethylhexyl (triazone|methoxycinnamate|salicylate)|'
        r'homosalate|avobenzone|butyl methoxydibenzoylmethane|bemotrizinol|'
        r'bis-ethylhexyloxyphenol|diethylamino hydroxybenzoyl|tinosorb|uvinul|'
        r'drometrizole|methylene bis-benzotriazolyl|isoamyl p-methoxycinnamate|oxybenzone',
      ),
      const ['spf', 'uv', 'спф', 'фильтр', 'sunscreen', 'санскрин'],
    ),
    // ---- "free of" ----
    IngredientGroup(
      'fragrance',
      'Без отдушки',
      IngredientKind.avoid,
      _re(r'parfum|fragrance|^aroma$'),
      const ['отдушк', 'парфюм', 'fragrance', 'parfum'],
    ),
    IngredientGroup(
      'fragrance_allergen',
      'Без ароматических аллергенов (список ЕС)',
      IngredientKind.avoid,
      FragranceAllergens.pattern,
      const ['аллерген', 'allergen'],
    ),
    IngredientGroup(
      'alcohol',
      'Без спирта',
      IngredientKind.avoid,
      _re(r'^(alcohol( denat\.?)?|sd alcohol.*|ethanol)$'),
      const ['спирт', 'alcohol', 'ethanol'],
    ),
    IngredientGroup(
      'paraben',
      'Без парабенов',
      IngredientKind.avoid,
      _re('paraben'),
      const ['парабен', 'paraben'],
    ),
    IngredientGroup(
      'silicone',
      'Без силиконов',
      IngredientKind.avoid,
      _re('dimethicone|siloxane|methicone|silicone|trimethylsiloxysilicate'),
      const ['силикон', 'silicone', 'dimethicone'],
    ),
    IngredientGroup(
      'sulfate',
      'Без сульфатов',
      IngredientKind.avoid,
      _re('(lauryl|laureth) sulfate|coco-sulfate'),
      const ['сульфат', 'sulfate', 'sls'],
    ),
  ];

  static final Map<String, IngredientGroup> _byCode = {
    for (final g in groups) g.code: g,
  };

  static IngredientGroup? byCode(String code) => _byCode[code];

  static List<IngredientGroup> ofKind(IngredientKind kind) => [
    for (final g in groups)
      if (g.kind == kind) g,
  ];

  /// Group codes found in [inci] (empty for an empty list). [uv] says whether
  /// the UV-filter group makes sense for the product: titanium dioxide and zinc
  /// oxide are plain pigments in makeup, and perfume carries UV absorbers only
  /// to protect the scent, so neither is "sun protection".
  static Set<String> detect(String inci, {bool uv = true}) {
    if (inci.trim().isEmpty) return const {};
    final key = '${uv ? 'u' : 'n'}|$inci';
    final cached = _cache[key];
    if (cached != null) return cached;
    final tokens = [
      for (final t in inci.toLowerCase().split(RegExp(r'\s*,\s*')))
        if (t.trim().isNotEmpty) ...[
          t.trim(),
          // "Citrus Limon (Lemon) Peel Oil" is also "citrus limon peel oil"
          if (t.contains('(')) FragranceAllergens.normalize(t),
        ],
    ];
    final found = <String>{
      for (final g in groups)
        if (!(!uv && g.code == 'uv_filter') &&
            tokens.any((t) => g.pattern.hasMatch(t)))
          g.code,
    };
    return _cache[key] = found;
  }

  static final Map<String, Set<String>> _cache = {};

  /// Search words that are too common inside other words to be used for free
  /// text ("гликол" is in "пропиленгликоль", "молочн" in "молочное мыло").
  static const _textUnsafe = {'гликол', 'glycol', 'молочн'};

  /// Safer words for the same groups, used only for free text.
  static const _textExtra = {
    'glycolic': ['гликолев', 'glycolic'],
    'lactic': ['молочная кислот', 'молочной кислот', 'lactic'],
  };

  /// Groups named in a free text (a product name typed by the user:
  /// "Сыворотка с ретинолом", "Vitamin C 15%", "BHA тоник"). Words shorter
  /// than 3 letters are ignored, so "ha" never matches half the alphabet.
  static Set<String> detectInText(String text) {
    final t = text.toLowerCase();
    if (t.trim().isEmpty) return const {};
    return {
      for (final g in groups)
        if (g.kind != IngredientKind.avoid &&
            [
              ...g.synonyms.where(
                (x) => x.length >= 3 && !_textUnsafe.contains(x),
              ),
              ...?_textExtra[g.code],
            ].any(t.contains))
          g.code,
    };
  }

  /// Groups found in a product.
  static Set<String> of(Product p) =>
      detect(p.inci, uv: p.category != 'Макияж' && p.category != 'Парфюмерия');

  /// Acids and actives of a product (not the "free of" groups), in the order
  /// of [groups].
  static List<IngredientGroup> activesOf(Product p) {
    final found = of(p);
    return [
      for (final g in groups)
        if (g.kind != IngredientKind.avoid && found.contains(g.code)) g,
    ];
  }

  /// The groups a search text points at ("ниацинамид", "bha", "salicylic").
  /// Needs at least 3 characters so a letter never matches half the catalog.
  static List<IngredientGroup> forQuery(String query) {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return const [];
    return [
      for (final g in groups)
        if (g.kind != IngredientKind.avoid &&
            g.synonyms.any(
              (s) => q == s || (q.length >= 3 && (s.startsWith(q))),
            ))
          g,
    ];
  }
}
