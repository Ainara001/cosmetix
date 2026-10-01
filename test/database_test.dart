import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/database/seed_data.dart';
import 'package:cosmetix/repositories/cart_repository.dart';
import 'package:cosmetix/repositories/chat_repository.dart';
import 'package:cosmetix/repositories/product_repository.dart';
import 'package:cosmetix/repositories/review_repository.dart';
import 'package:cosmetix/repositories/safety_repository.dart';
import 'package:cosmetix/repositories/user_repository.dart';
import 'package:cosmetix/services/assistant_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DatabaseHelper helper;
  late UserRepository users;
  late ProductRepository products;
  late CartRepository cart;
  late SafetyRepository safety;

  setUp(() async {
    helper = DatabaseHelper(path: inMemoryDatabasePath);
    users = UserRepository(helper);
    products = ProductRepository(helper);
    cart = CartRepository(helper);
    safety = SafetyRepository(helper);
  });

  tearDown(() => helper.close());

  test('seed data is created on first open', () async {
    final all = await products.getAll(1);
    expect(all.length, greaterThanOrEqualTo(15));
    expect((await products.getStorePrices(1)).length, 3);
    expect((await safety.ingredientsOf(1)).length, 5);
    expect((await safety.reactions(1)).length, 3);
  });

  group('users', () {
    test('login with the demo account', () async {
      final ok = await users.login(SeedData.demoEmail, SeedData.demoPassword);
      expect(ok, isNotNull);
      expect(ok!.firstName, 'Айнара');
      expect(await users.login(SeedData.demoEmail, 'wrong'), isNull);
    });

    test('register, duplicate e-mail, change password', () async {
      final u = await users.register(
        firstName: 'Мария',
        email: 'Maria@Mail.com',
        password: 'Secret123',
      );
      expect(u.email, 'maria@mail.com');
      expect(
        () => users.register(
          firstName: 'X',
          email: 'maria@mail.com',
          password: 'Secret123',
        ),
        throwsStateError,
      );
      expect(
        await users.changePassword('maria@mail.com', 'NewPass456'),
        isTrue,
      );
      expect(await users.login('maria@mail.com', 'NewPass456'), isNotNull);
      expect(
        (await safety.blacklist(u.id)).length,
        7,
      ); // defaults for new users
    });

    test('profile and beauty data are updated', () async {
      await users.updateProfile(
        id: 1,
        firstName: 'Новое',
        lastName: 'Имя',
        email: 'new@mail.com',
        phone: '',
        city: 'Алматы',
      );
      await users.updateBeauty(
        1,
        colorType: 'Осень',
        skinConcerns: ['Акне и высыпания'],
      );
      final u = (await users.getById(1))!;
      expect(u.firstName, 'Новое');
      expect(u.colorType, 'Осень');
      expect(u.skinConcerns, ['Акне и высыпания']);
    });
  });

  test('favorites are stored in SQLite', () async {
    expect(await products.toggleFavorite(1, 5), isTrue);
    expect((await products.getById(5, 1))!.isFavorite, isTrue);
    expect(await products.toggleFavorite(1, 5), isFalse);
    expect((await products.getById(5, 1))!.isFavorite, isFalse);
  });

  test('search history keeps unique queries', () async {
    await products.addHistory(1, 'крем');
    await products.addHistory(1, 'крем');
    await products.addHistory(1, '  ');
    expect(await products.getHistory(1), ['крем']);
    await products.clearHistory(1);
    expect(await products.getHistory(1), isEmpty);
  });

  test(
    'cart: add, change quantity, checkout creates an order and bonus',
    () async {
      await cart.add(1, 1, 1);
      await cart.add(1, 1, 1);
      await cart.add(1, 8, 2);
      var items = await cart.getItems(1);
      expect(items.length, 2);
      final first = items.firstWhere((i) => i.product.id == 1);
      expect(first.quantity, 2);
      expect(first.unitPrice, 2500); // price of store 1
      final second = items.firstWhere((i) => i.product.id == 8);
      expect(second.unitPrice, 1500 + 700); // price of store 2

      await cart.setQuantity(second.cartId, 3);
      final order = await cart.checkout(1);
      expect(order, isNotNull);
      expect(order!.total, 2500 * 2 + 2200 * 3);
      expect(await cart.getItems(1), isEmpty);
      expect((await users.getById(1))!.bonusPoints, order.bonus);
      expect((await cart.getOrders(1)).single.lines.length, 2);
      expect(await cart.checkout(1), isNull); // empty cart
    },
  );

  test('reactions diary: create, update, delete', () async {
    final id = await safety.addReaction(
      userId: 1,
      productId: 2,
      title: 'Отёк',
      severity: 4,
      date: DateTime(2026, 1, 5),
    );
    expect((await safety.reactions(1)).length, 4);
    await safety.updateReaction(
      id: id,
      productId: 2,
      title: 'Жжение',
      severity: 2,
      date: DateTime(2026, 1, 6),
    );
    expect((await safety.reactionById(id))!.title, 'Жжение');
    await safety.deleteReaction(id);
    expect(await safety.reactionById(id), isNull);
  });

  test('blacklist: toggle, add custom, delete', () async {
    final list = await safety.blacklist(1);
    final silicone = list.firstWhere((b) => b.name == 'Силиконы');
    await safety.setBlacklistEnabled(silicone.id, true);
    expect(
      (await safety.blacklist(
        1,
      )).firstWhere((b) => b.id == silicone.id).enabled,
      isTrue,
    );
    await safety.addCustom(1, 'Спирт');
    final custom = (await safety.blacklist(1)).last;
    expect(custom.isCustom, isTrue);
    await safety.deleteBlacklistItem(custom.id);
    expect((await safety.blacklist(1)).length, list.length);
  });

  test('reviews: add, edit, delete', () async {
    final repo = ReviewRepository(helper);
    final before = (await repo.forProduct(2)).length;
    await repo.add(
      productId: 2,
      userId: 1,
      author: 'Айнара',
      rating: 5,
      body: 'Отличная палетка!',
    );
    var list = await repo.forProduct(2);
    expect(list.length, before + 1);
    await repo.update(list.first.id, 3, 'Нормально, но не идеально');
    list = await repo.forProduct(2);
    expect(list.first.rating, 3);
    await repo.delete(list.first.id);
    expect((await repo.forProduct(2)).length, before);
  });

  test('chat: messages are persisted and can be reset', () async {
    final chat = ChatRepository(helper);
    expect((await chat.messages(1)).length, 3);
    await chat.add(1, 'Привет', isUser: true);
    expect((await chat.messages(1)).last.isUser, isTrue);
    await chat.reset(1);
    expect((await chat.messages(1)).length, 1);
  });

  group('assistant', () {
    test('compares prices of two brands', () async {
      final bot = AssistantService(products, safety);
      final answer = await bot.reply(
        'что меньше стоит: палетка FlowerKnows или Peripera?',
        1,
      );
      expect(answer, contains('Flower Knows'));
      expect(answer, contains('выигрывает по цене'));
    });

    test('answers about composition and falls back politely', () async {
      final bot = AssistantService(products, safety);
      expect(
        await bot.reply('какой состав у палетки Flower Knows', 1),
        contains('8.5/10'),
      );
      expect(await bot.reply('abracadabra', 1), contains('Я могу'));
    });
  });

  test('resetDemoData restores the seed', () async {
    await users.register(
      firstName: 'Тест',
      email: 't@t.com',
      password: 'Passw0rd1',
    );
    await helper.resetDemoData();
    expect(await users.emailExists('t@t.com'), isFalse);
    expect(await users.emailExists(SeedData.demoEmail), isTrue);
  });
}
