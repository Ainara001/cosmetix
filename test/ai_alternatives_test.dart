import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/core/beauty/beauty_codes.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/core/utils/formatters.dart';
import 'package:cosmetix/models/beauty_profile.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/models/social_models.dart';
import 'package:cosmetix/repositories/product_repository.dart';
import 'package:cosmetix/services/assistant_service.dart';
import 'package:cosmetix/services/recommendation_service.dart';

ChatMessage _msg(String text, {bool user = false}) => ChatMessage(
  id: 1,
  isUser: user,
  text: text,
  createdAt: DateTime(2026, 1, 1),
);

StorePrice _offer(int store, int price, int dist, {bool inStock = true}) =>
    StorePrice(
      storeId: store,
      storeName: 'Shop$store',
      distanceM: dist,
      address: 'Addr$store',
      rating: 0,
      price: price,
      inStock: inStock,
      qty: inStock ? 5 : 0,
    );

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DatabaseHelper helper;
  late PersonalizationContext ctx;

  setUp(() async {
    helper = DatabaseHelper(path: inMemoryDatabasePath);
    ctx = PersonalizationContext(
      profile: const BeautyProfile(colorType: ColorType.autumn),
      blacklist: const [],
      candidates: await ProductRepository(helper).candidates(1),
    );
  });
  tearDown(() => helper.close());

  group('which products get shop data', () {
    final history = [
      _msg('Посоветуй тинт', user: true),
      _msg('Подойдёт Wine Nude [#7].'),
    ];

    test('markers of the last answers are the products being discussed', () {
      expect(AssistantService.recentProductIds(history), [7]);
      expect(
        AssistantService.recentProductIds([
          _msg('[#3] и [#8]'),
          _msg('hi', user: true),
        ]),
        [3, 8],
      );
    });

    test('a follow-up without a product name still knows the product', () {
      final ids = AssistantService.shopProductIds(
        ctx: ctx,
        text: 'Сколько это стоит рядом?',
        history: history,
      );
      expect(ids, [7]);
    });

    test('"alternatives" adds the other lip products, not other kinds', () {
      final ids = AssistantService.shopProductIds(
        ctx: ctx,
        text: 'А что из альтернатив стоит дешевле в других магазинах?',
        history: history,
      );
      expect(ids.first, 7);
      expect(ids.toSet().containsAll({3, 8, 9}), isTrue); // lip products
      expect(ids.contains(5), isFalse); // a serum is not an alternative
      expect(ids.length, lessThanOrEqualTo(7));
    });

    test('no chat history and no product name: nothing is loaded', () {
      expect(
        AssistantService.shopProductIds(
          ctx: ctx,
          text: 'Есть альтернативы рядом?',
          history: const [],
        ),
        isEmpty,
      );
    });
  });

  group('the shop section of the prompt', () {
    final stores = StoreContext(
      located: true,
      nearest: const [],
      offers: {
        7: [_offer(1, 3000, 600), _offer(2, 2900, 5100)],
        8: [_offer(1, 1500, 600, inStock: false), _offer(3, 1700, 900)],
        3: [_offer(4, 3500, 2000)],
      },
    );

    test('several products: nearest and cheapest with stock, real numbers', () {
      final text = AssistantService.shopsForTest(stores, shareProfile: true);
      expect(text, contains('use ONLY these prices'));
      expect(text, contains('[#7] nearest with stock: Shop1'));
      expect(text, contains('cheapest with stock: Shop2'));
      expect(text, contains(Formatters.price(2900)));
      // #8: the nearest shop is out of stock, so the one with stock is named
      expect(text, contains('[#8] nearest with stock: Shop3'));
      expect(text, isNot(contains(Formatters.price(1500))));
    });

    test('a product out of stock everywhere is said so', () {
      final s = StoreContext(
        located: true,
        nearest: const [],
        offers: {
          1: [_offer(1, 100, 10, inStock: false)],
          2: [_offer(1, 100, 10, inStock: false)],
          3: [_offer(1, 100, 10, inStock: false)],
        },
      );
      expect(
        AssistantService.shopsForTest(s, shareProfile: true),
        contains('[#1]: out of stock in every shop'),
      );
    });

    test('the rules forbid invented prices and allow naming alternatives', () {
      final prompt = AssistantService.buildSystemPrompt(
        ctx: ctx,
        question: 'Есть альтернативы?',
        language: 'Russian',
        shareProfile: true,
        stores: stores,
      );
      expect(prompt, contains('NEVER invent a price'));
      expect(
        prompt,
        contains('EXCEPTION: when the user asks for alternatives'),
      );
      expect(prompt.length, lessThan(6500)); // fits the 6000-char limit
    });
  });
}
