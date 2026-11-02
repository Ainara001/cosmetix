import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/core/beauty/beauty_codes.dart';
import 'package:cosmetix/core/beauty/color_palettes.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/models/beauty_profile.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/models/product_filter.dart';
import 'package:cosmetix/models/recommendation.dart';
import 'package:cosmetix/repositories/product_repository.dart';
import 'package:cosmetix/services/assistant_service.dart';
import 'package:cosmetix/services/color_test_service.dart';
import 'package:cosmetix/services/ingredient_catalog.dart';
import 'package:cosmetix/services/recommendation_service.dart';

Product _p(
  String name, {
  String inci = '',
  String category = 'Уход за лицом',
  int? shade,
  String description = '',
}) => Product(
  id: name.hashCode & 0xFFFF,
  brand: 'B',
  name: name,
  category: category,
  zone: '',
  price: 1000,
  inStock: true,
  art: 'bottle',
  color: 0,
  description: description,
  naturalPercent: 80,
  createdAt: 0,
  inci: inci,
  shade: shade,
);

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('composition: what is found in an INCI list', () {
    test('acids and actives are recognised by their INCI names', () {
      final found = IngredientCatalog.detect(
        'Water, Sodium Hyaluronate, Niacinamide, Salicylic Acid, '
        'Glycolic Acid, Panthenol, Parfum',
      );
      expect(
        found,
        containsAll([
          'hyaluronic',
          'niacinamide',
          'salicylic',
          'glycolic',
          'panthenol',
          'fragrance',
        ]),
      );
      expect(found, isNot(contains('retinoid')));
    });

    test('look-alikes are not mistaken for the real thing', () {
      final found = IngredientCatalog.detect(
        'Cetearyl Alcohol, Magnesium Sulfate, Polyglyceryl-3 Diisostearate',
      );
      expect(found, isNot(contains('alcohol'))); // a fatty alcohol, not ethanol
      expect(found, isNot(contains('sulfate'))); // not a lauryl sulfate
      expect(found, isNot(contains('glycerin')));
      expect(
        IngredientCatalog.detect('Alcohol Denat., Sodium Laureth Sulfate'),
        containsAll(['alcohol', 'sulfate']),
      );
    });

    test(
      'UV filters count only for skincare, not makeup pigments or perfume',
      () {
        const inci = 'Water, Titanium Dioxide (CI 77891), Zinc Oxide';
        expect(IngredientCatalog.detect(inci), contains('uv_filter'));
        expect(
          IngredientCatalog.detect(inci, uv: false),
          isNot(contains('uv_filter')),
        );
        final pigment = _p('Palette', inci: inci, category: 'Макияж');
        final scent = _p(
          'Perfume',
          inci: 'Octocrylene, Parfum',
          category: 'Парфюмерия',
        );
        final sun = _p('Sunscreen', inci: inci);
        expect(IngredientCatalog.activesOf(pigment), isEmpty);
        expect(IngredientCatalog.activesOf(scent), isEmpty);
        expect(
          IngredientCatalog.activesOf(sun).map((g) => g.code),
          contains('uv_filter'),
        );
      },
    );

    test('an empty list finds nothing', () {
      expect(IngredientCatalog.detect(''), isEmpty);
    });
  });

  group('composition: the filter', () {
    final serum = _p('Serum', inci: 'Water, Niacinamide, Sodium Hyaluronate');
    final toner = _p(
      'Toner',
      inci: 'Water, Salicylic Acid, Niacinamide, Parfum',
    );
    final cream = _p('Cream', inci: 'Water, Glycerin, Ceramide NP');
    final gift = _p('Gift set'); // no published composition
    final all = [serum, toner, cream, gift];

    List<String> run(ProductFilter f) => [
      for (final p in all)
        if (f.matches(p)) p.name,
    ];

    test('"all selected" needs every ingredient, "any" needs one', () {
      const both = {'niacinamide', 'hyaluronic'};
      expect(run(const ProductFilter(withIngredients: both)), ['Serum']);
      expect(
        run(const ProductFilter(withIngredients: both, anyIngredient: true)),
        ['Serum', 'Toner'],
      );
    });

    test('"free of" drops products with it and those with unknown INCI', () {
      expect(run(const ProductFilter(withoutIngredients: {'fragrance'})), [
        'Serum',
        'Cream',
      ]);
    });

    test('acid + "free of" combine', () {
      expect(
        run(
          const ProductFilter(
            withIngredients: {'niacinamide'},
            withoutIngredients: {'fragrance'},
          ),
        ),
        ['Serum'],
      );
    });

    test('the search box finds ingredients by name, synonym or INCI text', () {
      expect(run(const ProductFilter(name: 'ниацинамид')), ['Serum', 'Toner']);
      expect(run(const ProductFilter(name: 'bha')), ['Toner']);
      expect(run(const ProductFilter(name: 'ceramide')), ['Cream']);
      expect(run(const ProductFilter(name: 'Gift')), ['Gift set']);
    });

    test('isDefault turns false once an ingredient is chosen', () {
      expect(const ProductFilter().isDefault, isTrue);
      expect(const ProductFilter(withIngredients: {'zinc'}).isDefault, isFalse);
    });
  });

  group('composition: the real catalog', () {
    late DatabaseHelper helper;
    late List<Product> products;
    late ProductRepository repo;

    setUp(() async {
      helper = DatabaseHelper(path: inMemoryDatabasePath);
      repo = ProductRepository(helper);
      products = await repo.getAll(1);
    });
    tearDown(() => helper.close());

    Set<String> names(ProductFilter f) => {
      for (final p in products)
        if (f.matches(p)) p.name,
    };

    test(
      'niacinamide finds The Ordinary serum, hyaluronic finds the essence',
      () {
        expect(
          names(const ProductFilter(withIngredients: {'niacinamide'})),
          contains('Niacinamide 10% + Zinc 1%'),
        );
        expect(
          names(const ProductFilter(withIngredients: {'hyaluronic'})),
          contains('Advanced Snail 96 Mucin Power Essence'),
        );
      },
    );

    test('every chip of the filter screen matches something or is honest', () {
      for (final g in IngredientCatalog.groups) {
        // must not throw and must give a stable result on the real data
        final f = g.kind == IngredientKind.avoid
            ? ProductFilter(withoutIngredients: {g.code})
            : ProductFilter(withIngredients: {g.code});
        expect(names(f), isA<Set<String>>(), reason: g.code);
      }
      // at least the main actives exist in the demo catalog
      for (final code in ['niacinamide', 'hyaluronic', 'ceramide']) {
        expect(
          names(ProductFilter(withIngredients: {code})),
          isNotEmpty,
          reason: code,
        );
      }
    });
  });

  group('shades: real colour against the colour type', () {
    test('the closest palette of a few known colours', () {
      expect(
        ShadeMatcher.closestSeason(0xFFF48C93),
        ColorType.spring,
      ); // coral pink
      expect(
        ShadeMatcher.closestSeason(0xFFDDB1B6),
        ColorType.summer,
      ); // cool pink
      expect(ShadeMatcher.closestSeason(0xFF753E44), ColorType.winter); // wine
      expect(
        ShadeMatcher.closestSeason(0xFFB5532F),
        ColorType.autumn,
      ); // terracotta
    });

    test('a colour of the palette is a perfect match, a far one is not', () {
      expect(
        ShadeMatcher.similarity(0xFFEE6F5B, ColorType.spring),
        closeTo(1, 0.001),
      );
      expect(
        ShadeMatcher.similarity(0xFF7A1F3D, ColorType.spring),
        lessThan(0.3),
      );
    });

    test('skin: a light beige base fits light skin, not deep skin', () {
      const base = 0xFFE3C1A6;
      expect(
        ShadeMatcher.skinSimilarity(base, SkinTone.light, Undertone.warm),
        greaterThan(0.55),
      );
      expect(
        ShadeMatcher.skinSimilarity(base, SkinTone.deep, Undertone.warm),
        lessThan(0.2),
      );
    });

    group('ranking with the seeded catalog', () {
      late List<ProductCandidate> candidates;
      late DatabaseHelper helper;

      setUp(() async {
        helper = DatabaseHelper(path: inMemoryDatabasePath);
        candidates = await ProductRepository(helper).candidates(1);
      });
      tearDown(() => helper.close());

      Recommendation rec(BeautyProfile p, String name) =>
          RecommendationService.rank(
            candidates: candidates,
            profile: p,
            blacklist: const [],
          ).firstWhere((r) => r.product.name.contains(name));

      test('the catalog really stores the shades (DB v8+)', () {
        final withShade = candidates.where((c) => c.product.shade != null);
        expect(withShade.length, 8);
        expect(DatabaseHelper.dbVersion, 10);
      });

      test('a Spring person: coral tint fits, wine tint is flagged', () {
        const spring = BeautyProfile(
          colorType: ColorType.spring,
          undertone: Undertone.warm,
          skinTone: SkinTone.light,
        );
        final berry = rec(spring, 'Happy Berry');
        final wine = rec(spring, 'Wine Nude');
        expect(berry.score, greaterThan(wine.score));
        expect(
          berry.reasons.map((r) => r.type),
          contains(MatchReasonType.shadeFit),
        );
        final off = wine.reasons.firstWhere(
          (r) => r.type == MatchReasonType.shadeOff,
        );
        expect(off.detail, 'Зима'); // says which palette it belongs to
      });

      test('a Winter person gets the opposite verdict', () {
        const winter = BeautyProfile(
          colorType: ColorType.winter,
          undertone: Undertone.cool,
          skinTone: SkinTone.light,
        );
        final berry = rec(winter, 'Happy Berry');
        final wine = rec(winter, 'Wine Nude');
        expect(wine.score, greaterThan(berry.score));
        expect(
          wine.reasons.map((r) => r.type),
          contains(MatchReasonType.shadeFit),
        );
      });

      test('cool-pink blush: Summer fits, Autumn does not', () {
        final summer = rec(
          const BeautyProfile(
            colorType: ColorType.summer,
            undertone: Undertone.cool,
          ),
          'Better Than Cheek',
        );
        final autumn = rec(
          const BeautyProfile(
            colorType: ColorType.autumn,
            undertone: Undertone.warm,
          ),
          'Better Than Cheek',
        );
        expect(summer.score, greaterThan(autumn.score));
      });

      test('a cushion is matched with the skin tone, not the palette', () {
        const light = BeautyProfile(
          colorType: ColorType.spring,
          skinTone: SkinTone.light,
          undertone: Undertone.warm,
        );
        const deep = BeautyProfile(
          colorType: ColorType.spring,
          skinTone: SkinTone.deep,
          undertone: Undertone.warm,
        );
        expect(
          rec(light, 'Magic Cushion').reasons.map((r) => r.type),
          contains(MatchReasonType.skinShade),
        );
        expect(
          rec(deep, 'Magic Cushion').reasons.map((r) => r.type),
          contains(MatchReasonType.skinShadeOff),
        );
      });

      test('skincare is not affected by shades', () {
        const spring = BeautyProfile(colorType: ColorType.spring);
        final r = rec(spring, 'Niacinamide');
        expect(
          r.reasons.map((x) => x.type),
          isNot(contains(MatchReasonType.shadeOff)),
        );
      });
    });
  });

  group('colour test', () {
    test('contrast decides between the soft and the clear half', () {
      // warm, not very dark: contrast splits Весна (clear) / Осень (soft)
      expect(
        ColorTestService.compute(
          warm: 3,
          depth: 1,
          vein: 0,
          contrast: 2,
        ).colorType,
        'Весна',
      );
      expect(
        ColorTestService.compute(
          warm: 3,
          depth: 1,
          vein: 0,
          contrast: -2,
        ).colorType,
        'Осень',
      );
      // cool: sharp contrast gives Зима even with medium depth
      expect(
        ColorTestService.compute(
          warm: -3,
          depth: 1,
          vein: -3,
          contrast: 2,
        ).colorType,
        'Зима',
      );
      expect(
        ColorTestService.compute(
          warm: -3,
          depth: 1,
          vein: -3,
          contrast: -2,
        ).colorType,
        'Лето',
      );
    });

    test('the questionnaire now also asks about metal, contrast and white', () {
      final sections = ColorTestService.questions.map((q) => q.section);
      expect(sections, containsAll(['Украшения', 'Контраст', 'Белое']));
      expect(ColorTestService.questions.length, 8);
      expect(
        ColorTestService.questions.every((q) => q.options.length >= 3),
        isTrue,
      );
    });

    test('every season has a palette with colours to wear and to avoid', () {
      for (final t in ColorType.values) {
        final p = ColorPalettes.seasons[t]!;
        expect(p.flattering.length, greaterThanOrEqualTo(6), reason: t.code);
        expect(p.avoid, isNotEmpty, reason: t.code);
      }
    });
  });

  group('AI prompt uses the test results', () {
    late DatabaseHelper helper;
    late PersonalizationContext ctx;

    setUp(() async {
      helper = DatabaseHelper(path: inMemoryDatabasePath);
      final candidates = await ProductRepository(helper).candidates(1);
      ctx = PersonalizationContext(
        profile: const BeautyProfile(
          colorType: ColorType.spring,
          undertone: Undertone.warm,
          skinTone: SkinTone.light,
          skinType: SkinType.dry,
        ),
        blacklist: const [],
        candidates: candidates,
      );
    });
    tearDown(() => helper.close());

    String prompt({required bool share, String q = 'Посоветуй тинт'}) =>
        AssistantService.buildSystemPrompt(
          ctx: ctx,
          question: q,
          language: 'Russian',
          shareProfile: share,
        );

    test('with consent every product carries the app\'s own "fits" facts', () {
      final text = prompt(share: true);
      expect(text, contains('fits '));
      expect(text, contains('undertone Тёплый'));
      expect(text, contains('shade matches skin tone Светлый'));
      expect(text, contains('shade matches palette Весна'));
      // a shade of another palette is marked so the model does not praise it
      expect(text, contains('NOT the user\'s'));
      expect(text, contains('good makeup colors (Весна)'));
      expect(text, contains('avoid:'));
    });

    test(
      'acids and actives are listed per product for ingredient questions',
      () {
        final text = prompt(share: false, q: 'Где ниацинамид?');
        expect(text, contains('has:'));
        expect(text, contains('Ниацинамид (B3)'));
        expect(text, contains('Гиалуроновая кислота'));
      },
    );

    test('without consent no test result leaves the phone', () {
      final text = prompt(share: false);
      final data = text.split('USER BEAUTY PROFILE:').last; // after the rules
      expect(text, isNot(contains('Весна')));
      expect(data, isNot(contains('fits ')));
      expect(data, isNot(contains('good makeup colors')));
      expect(data, isNot(contains('match:')));
    });
  });
}
