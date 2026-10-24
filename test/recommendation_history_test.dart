import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/core/beauty/beauty_codes.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/models/beauty_profile.dart';
import 'package:cosmetix/models/care_models.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/models/recommendation.dart';
import 'package:cosmetix/models/safety_models.dart';
import 'package:cosmetix/repositories/care_repository.dart';
import 'package:cosmetix/repositories/product_repository.dart';
import 'package:cosmetix/repositories/safety_repository.dart';
import 'package:cosmetix/repositories/user_repository.dart';
import 'package:cosmetix/services/recommendation_service.dart';

Product _p(int id, {int natural = 80}) => Product(
  id: id,
  brand: 'B',
  name: 'P$id',
  category: 'Уход за лицом',
  zone: '',
  price: 1000,
  inStock: true,
  art: 'bottle',
  color: 0,
  description: '',
  naturalPercent: natural,
  createdAt: DateTime(2026, 1, 1).millisecondsSinceEpoch,
);

ProductCandidate _c(
  Product p, {
  Set<String> tags = const {},
  List<Ingredient> ingredients = const [],
}) => ProductCandidate(
  product: p,
  skinTypes: const {SkinType.dry},
  tags: tags,
  ingredients: ingredients,
);

Ingredient _ing(String name, {int risk = 0}) => Ingredient(
  id: name.hashCode,
  name: name,
  description: '',
  risk: risk,
  isAllergen: false,
);

const _profile = BeautyProfile(
  skinType: SkinType.dry,
  colorType: ColorType.spring,
);

double _score(List<Recommendation> r, int id) =>
    r.firstWhere((e) => e.product.id == id).score;

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final now = DateTime(2026, 1, 2);

  List<Recommendation> rank(
    List<ProductCandidate> cs, {
    BeautyProfile profile = _profile,
    PersonalHistory history = const PersonalHistory.empty(),
  }) => RecommendationService.rank(
    candidates: cs,
    profile: profile,
    blacklist: const [],
    history: history,
    now: now,
  );

  group('preferences', () {
    test('parse / encode only keep known codes', () {
      expect(Preferences.parse('natural|bogus|fragrance_free'), {
        'natural',
        'fragrance_free',
      });
      expect(Preferences.parse(null), isEmpty);
      expect(Preferences.encode({'natural', 'zzz'}), 'natural');
    });

    test(
      '"no fragrance" lifts fragrance-free and lowers fragranced products',
      () {
        final plain = _c(_p(1), ingredients: [_ing('Вода')]);
        final scented = _c(_p(2), ingredients: [_ing('Parfum', risk: 1)]);
        final without = rank([plain, scented]);
        final withPref = rank(
          [plain, scented],
          profile: const BeautyProfile(
            skinType: SkinType.dry,
            colorType: ColorType.spring,
            preferences: {Preferences.fragranceFree},
          ),
        );
        expect(_score(withPref, 1), greaterThan(_score(without, 1)));
        expect(_score(withPref, 2), lessThan(_score(without, 2)));
        expect(
          withPref
              .firstWhere((r) => r.product.id == 1)
              .reasons
              .any((r) => r.type == MatchReasonType.preference),
          isTrue,
        );
        // a preference never hides a product
        expect(withPref.length, 2);
      },
    );

    test('"natural" prefers high natural share', () {
      final natural = _c(_p(1, natural: 95));
      final chem = _c(_p(2, natural: 20));
      final r = rank(
        [natural, chem],
        profile: const BeautyProfile(
          skinType: SkinType.dry,
          colorType: ColorType.spring,
          preferences: {Preferences.natural},
        ),
      );
      expect(r.first.product.id, 1);
      expect(_score(r, 1), greaterThan(_score(r, 2)));
    });

    test('preferences are part of the profile signature', () {
      const a = BeautyProfile(skinType: SkinType.dry);
      const b = BeautyProfile(
        skinType: SkinType.dry,
        preferences: {Preferences.natural},
      );
      expect(a.signature, isNot(b.signature));
    });
  });

  group('history (only when allowed)', () {
    test('a product with a noted reaction is ranked lower, with a reason', () {
      final a = _c(_p(1), ingredients: [_ing('Вода')]);
      final b = _c(_p(2), ingredients: [_ing('Вода')]);
      final plain = rank([a, b]);
      final r = rank([
        a,
        b,
      ], history: const PersonalHistory(reactedProducts: {1: 4}));
      expect(_score(r, 1), lessThan(_score(plain, 1)));
      expect(_score(r, 2), _score(plain, 2));
      expect(r.first.product.id, 2);
      final reasons = r.firstWhere((e) => e.product.id == 1).reasons;
      expect(
        reasons.any(
          (x) => x.type == MatchReasonType.previousReaction && x.detail == '4',
        ),
        isTrue,
      );
    });

    test('a worse reaction lowers the score more, within a cap', () {
      final a = _c(_p(1), ingredients: [_ing('Вода')]);
      double at(int s) => _score(
        rank([a], history: PersonalHistory(reactedProducts: {1: s})),
        1,
      );
      expect(at(5), lessThan(at(1)));
      expect(_score(rank([a]), 1) - at(5), lessThanOrEqualTo(0.32 + 1e-9));
    });

    test('a shared cautionary ingredient lowers the score a little', () {
      final shares = _c(_p(1), ingredients: [_ing('Parfum', risk: 1)]);
      final clean = _c(_p(2), ingredients: [_ing('Вода')]);
      final r = rank([
        shares,
        clean,
      ], history: const PersonalHistory(sharedRiskIngredients: {'Parfum'}));
      final plain = rank([shares, clean]);
      expect(_score(r, 1), lessThan(_score(plain, 1)));
      expect(_score(r, 2), _score(plain, 2));
    });

    test('owned products get a note but keep their score', () {
      final a = _c(_p(1), ingredients: [_ing('Вода')]);
      final r = rank([a], history: const PersonalHistory(ownedProductIds: {1}));
      expect(r.single.score, _score(rank([a]), 1));
      expect(
        r.single.reasons.any((x) => x.type == MatchReasonType.owned),
        isTrue,
      );
    });

    test('the blacklist stays a hard rule whatever the history says', () {
      const bl = BlacklistItem(
        id: 1,
        name: 'Парабены',
        description: '',
        enabled: true,
        isCustom: false,
        groupKey: 'paraben',
      );
      final bad = _c(
        _p(1),
        ingredients: [
          const Ingredient(
            id: 9,
            name: 'Парабены',
            description: '',
            risk: 2,
            isAllergen: true,
            groupKey: 'paraben',
          ),
        ],
      );
      final r = RecommendationService.rank(
        candidates: [bad],
        profile: _profile,
        blacklist: const [bl],
        history: const PersonalHistory(ownedProductIds: {1}),
        now: now,
      );
      expect(r, isEmpty);
    });
  });

  group('consent and loading from SQLite', () {
    late DatabaseHelper helper;
    late RecommendationService service;
    late UserRepository users;
    late CareRepository care;

    setUp(() async {
      helper = DatabaseHelper(path: inMemoryDatabasePath);
      users = UserRepository(helper);
      care = CareRepository(helper);
      service = RecommendationService(
        ProductRepository(helper),
        SafetyRepository(helper),
        users,
        care,
      );
      await helper.database;
    });
    tearDown(() => helper.close());

    test('without consent the history is never loaded', () async {
      await care.addToBag(1, const MyProduct(id: 0, name: 'Мой', productId: 2));
      final ctx = await service.loadContext(1);
      expect(ctx.history.isEmpty, isTrue);
      expect((await users.getById(1))!.recoUseHistory, isFalse);
    });

    test('with consent reactions and the bag are loaded', () async {
      await care.addToBag(1, const MyProduct(id: 0, name: 'Мой', productId: 2));
      await users.updatePreferences(1, useHistory: true);
      final ctx = await service.loadContext(1);
      // the demo diary has reactions to products 3, 4 and 15
      expect(ctx.history.reactedProducts.keys, containsAll([3, 4, 15]));
      expect(ctx.history.reactedProducts[4], 5);
      expect(ctx.history.ownedProductIds, {2});
    });

    test('preferences and consent are saved and read back', () async {
      await users.updatePreferences(
        1,
        preferences: {Preferences.natural, Preferences.fragranceFree},
        useHistory: true,
      );
      final u = (await users.getById(1))!;
      expect(u.preferences, {Preferences.natural, Preferences.fragranceFree});
      expect(u.recoUseHistory, isTrue);
      expect(u.beautyProfile.preferences, u.preferences);
      await users.updatePreferences(1, useHistory: false);
      final again = (await users.getById(1))!;
      expect(again.recoUseHistory, isFalse);
      expect(again.preferences, u.preferences); // untouched
    });
  });
}
