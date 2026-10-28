import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/core/beauty/beauty_codes.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/models/beauty_profile.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/models/recommendation.dart';
import 'package:cosmetix/models/safety_models.dart';
import 'package:cosmetix/repositories/product_repository.dart';
import 'package:cosmetix/repositories/safety_repository.dart';
import 'package:cosmetix/repositories/user_repository.dart';
import 'package:cosmetix/services/recommendation_service.dart';

Product _p(
  int id,
  String category, {
  int price = 1000,
  int ageDays = 0,
  bool inStock = true,
}) => Product(
  id: id,
  brand: 'B',
  name: 'P$id',
  category: category,
  zone: '',
  price: price,
  inStock: inStock,
  art: 'bottle',
  color: 0,
  description: '',
  naturalPercent: 80,
  createdAt: DateTime(2026, 1, 1).millisecondsSinceEpoch - ageDays * 86400000,
);

ProductCandidate _c(
  Product p, {
  Set<SkinType> skin = const {},
  Set<ColorType> colors = const {},
  Set<Undertone> under = const {},
  Set<SkinConcern> concerns = const {},
  Set<String> tags = const {},
  List<Ingredient> ingredients = const [],
}) => ProductCandidate(
  product: p,
  skinTypes: skin,
  colorTypes: colors,
  undertones: under,
  concerns: concerns,
  tags: tags,
  ingredients: ingredients,
);

const _paraben = Ingredient(
  id: 1,
  name: 'Парабены',
  description: '',
  risk: 2,
  isAllergen: true,
  groupKey: 'paraben',
);
const _water = Ingredient(
  id: 2,
  name: 'Вода',
  description: '',
  risk: 0,
  isAllergen: false,
);
const _blParaben = BlacklistItem(
  id: 1,
  name: 'Парабены',
  description: '',
  enabled: true,
  isCustom: false,
  groupKey: 'paraben',
);

final _now = DateTime(2026, 1, 1);

void main() {
  group('blacklist is a hard rule', () {
    final good = _c(
      _p(1, 'Макияж'),
      colors: {ColorType.summer},
      ingredients: [_water],
    );
    final bad = _c(
      _p(2, 'Макияж'),
      colors: {ColorType.summer}, // a perfect match for the user...
      under: {Undertone.cool},
      ingredients: [_paraben, _water], // ...but contains a blacklisted item
    );
    const profile = BeautyProfile(
      colorType: ColorType.summer,
      undertone: Undertone.cool,
    );

    test('a blacklisted product never appears, even with the best score', () {
      final r = RecommendationService.rank(
        candidates: [bad, good],
        profile: profile,
        blacklist: [_blParaben],
        now: _now,
      );
      expect(r.map((e) => e.product.id), [1]);
    });

    test('a disabled blacklist item does not exclude anything', () {
      const off = BlacklistItem(
        id: 1,
        name: 'Парабены',
        description: '',
        enabled: false,
        isCustom: false,
        groupKey: 'paraben',
      );
      final r = RecommendationService.rank(
        candidates: [bad, good],
        profile: profile,
        blacklist: [off],
        now: _now,
      );
      expect(r.map((e) => e.product.id), containsAll([1, 2]));
    });

    test('a custom blacklist word matches an ingredient name', () {
      const custom = BlacklistItem(
        id: 9,
        name: 'вода',
        description: '',
        enabled: true,
        isCustom: true,
      );
      final r = RecommendationService.rank(
        candidates: [good],
        profile: profile,
        blacklist: [custom],
        now: _now,
      );
      expect(r, isEmpty);
    });

    test(
      'with the real database: seeded products with parabens are excluded',
      () async {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        final helper = DatabaseHelper(path: inMemoryDatabasePath);
        addTearDown(helper.close);
        final service = RecommendationService(
          ProductRepository(helper),
          SafetyRepository(helper),
          UserRepository(helper),
        );
        final ctx = await service.loadContext(1); // demo user: parabens enabled
        expect(
          ctx.blacklist.any((b) => b.enabled && b.groupKey == 'paraben'),
          isTrue,
        );
        final ranked = RecommendationService.rank(
          candidates: ctx.candidates,
          profile: ctx.profile,
          blacklist: ctx.blacklist,
        );
        // CeraVe (14) and Nivea Soft (15) contain parabens in the seed data
        expect(
          ranked.any((r) => r.product.id == 14 || r.product.id == 15),
          isFalse,
        );
        expect(ranked, isNotEmpty);
        // and the exclusion holds for every product that is returned
        for (final r in ranked) {
          final c = ctx.candidates.firstWhere(
            (c) => c.product.id == r.product.id,
          );
          expect(
            RecommendationService.isBlacklisted(c, ctx.blacklist),
            isFalse,
          );
        }
      },
    );
  });

  group('skin type', () {
    final dryCream = _c(
      _p(1, 'Уход за лицом'),
      skin: {SkinType.dry},
      concerns: {SkinConcern.dryness},
      tags: {'hydrating'},
    );
    final oilyGel = _c(
      _p(2, 'Уход за лицом'),
      skin: {SkinType.oily},
      concerns: {SkinConcern.acne},
      tags: {'oil_control'},
    );

    test('dry skin ranks the dry-skin cream first', () {
      final r = RecommendationService.rank(
        candidates: [oilyGel, dryCream],
        profile: const BeautyProfile(
          skinType: SkinType.dry,
          concerns: {SkinConcern.dryness},
        ),
        blacklist: const [],
        now: _now,
      );
      expect(r.first.product.id, 1);
      expect(r.first.score, greaterThan(r.last.score));
      expect(
        r.first.reasons.map((e) => e.type),
        contains(MatchReasonType.skinType),
      );
    });

    test('oily skin with acne flips the order', () {
      final r = RecommendationService.rank(
        candidates: [dryCream, oilyGel],
        profile: const BeautyProfile(
          skinType: SkinType.oily,
          concerns: {SkinConcern.acne},
        ),
        blacklist: const [],
        now: _now,
      );
      expect(r.first.product.id, 2);
    });

    test('sensitive skin penalizes allergens', () {
      final plain = _c(_p(1, 'Уход за лицом'), ingredients: [_water]);
      final irritating = _c(
        _p(2, 'Уход за лицом'),
        ingredients: [
          const Ingredient(
            id: 3,
            name: 'Parfum',
            description: '',
            risk: 1,
            isAllergen: true,
          ),
        ],
      );
      final r = RecommendationService.rank(
        candidates: [irritating, plain],
        profile: const BeautyProfile(skinType: SkinType.sensitive),
        blacklist: const [],
        now: _now,
      );
      expect(r.first.product.id, 1);
    });
  });

  group('color type', () {
    final summerLip = _c(
      _p(1, 'Макияж'),
      colors: {ColorType.summer},
      under: {Undertone.cool},
    );
    final autumnLip = _c(
      _p(2, 'Макияж'),
      colors: {ColorType.autumn},
      under: {Undertone.warm},
    );

    test('color cosmetics follow color type and undertone', () {
      final summer = RecommendationService.rank(
        candidates: [autumnLip, summerLip],
        profile: const BeautyProfile(
          colorType: ColorType.summer,
          undertone: Undertone.cool,
        ),
        blacklist: const [],
        now: _now,
      );
      expect(summer.first.product.id, 1);
      final autumn = RecommendationService.rank(
        candidates: [summerLip, autumnLip],
        profile: const BeautyProfile(
          colorType: ColorType.autumn,
          undertone: Undertone.warm,
        ),
        blacklist: const [],
        now: _now,
      );
      expect(autumn.first.product.id, 2);
    });

    test('skincare ignores color type', () {
      final a = _c(_p(1, 'Уход за лицом'), colors: {ColorType.summer});
      final b = _c(_p(2, 'Уход за лицом'), colors: {ColorType.autumn});
      final r = RecommendationService.rank(
        candidates: [a, b],
        profile: const BeautyProfile(colorType: ColorType.summer),
        blacklist: const [],
        now: _now,
      );
      expect((r[0].score - r[1].score).abs(), lessThan(1e-9));
    });

    test('the full profile is reflected: summer + cool + dry + sensitive', () {
      const profile = BeautyProfile(
        colorType: ColorType.summer,
        undertone: Undertone.cool,
        skinType: SkinType.dry,
        concerns: {SkinConcern.sensitivity},
      );
      final best = _c(
        _p(1, 'Макияж'),
        colors: {ColorType.summer},
        under: {Undertone.cool},
        skin: {SkinType.dry},
      );
      final worst = _c(
        _p(2, 'Макияж'),
        colors: {ColorType.autumn},
        under: {Undertone.warm},
        skin: {SkinType.oily},
      );
      final r = RecommendationService.rank(
        candidates: [worst, best],
        profile: profile,
        blacklist: const [],
        now: _now,
      );
      expect(r.first.product.id, 1);
      expect(r.first.matchPercent, greaterThan(r.last.matchPercent));
      expect(
        r.first.reasons.map((e) => e.type),
        containsAll([
          MatchReasonType.colorType,
          MatchReasonType.undertone,
          MatchReasonType.skinType,
        ]),
      );
    });
  });

  test('newness is only a small factor', () {
    final fresh = _c(_p(1, 'Уход за лицом', ageDays: 0));
    final old = _c(_p(2, 'Уход за лицом', ageDays: 200));
    final r = RecommendationService.rank(
      candidates: [old, fresh],
      profile: const BeautyProfile(),
      blacklist: const [],
      now: _now,
    );
    expect(r.first.product.id, 1);
    expect(r.first.score - r.last.score, lessThan(0.11));
  });
}
