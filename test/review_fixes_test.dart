import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/core/utils/app_paths.dart';
import 'package:cosmetix/core/utils/password_hasher.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/database/seed_data.dart';
import 'package:cosmetix/providers/auth_provider.dart';
import 'package:cosmetix/repositories/cart_repository.dart';
import 'package:cosmetix/repositories/review_repository.dart';
import 'package:cosmetix/repositories/user_repository.dart';
import 'package:cosmetix/services/ai/ai_config.dart';

String _legacyHash(String password) =>
    sha256.convert(utf8.encode('cosmetix.local.v1:$password')).toString();

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('password hashing', () {
    test('hash is salted and verifies', () {
      final a = PasswordHasher.hash('Secret123');
      final b = PasswordHasher.hash('Secret123');
      expect(a, isNot(b)); // different salt every time
      expect(a, startsWith('pbkdf2\$'));
      expect(PasswordHasher.verify('Secret123', a), isTrue);
      expect(PasswordHasher.verify('Secret124', a), isFalse);
      expect(PasswordHasher.needsUpgrade(a), isFalse);
    });

    test('output matches Python hashlib.pbkdf2_hmac (known values)', () {
      // salt "salt" is c2FsdA== in base64
      expect(
        PasswordHasher.verify(
          'passwd',
          'pbkdf2\$1\$c2FsdA==\$VawEblbjCJ/sFpHCJUS2BflBhSFt3gRl5oudV8INrLw=',
        ),
        isTrue,
      );
      const ten =
          'pbkdf2\$10000\$c2FsdA==\$WxhWzPdnI39FyX52yK6eoM4EJCtMPUibj/X9bAxELvQ=';
      expect(PasswordHasher.verify('Cosmetix123', ten), isTrue);
      expect(PasswordHasher.verify('cosmetix123', ten), isFalse);
    });

    test('old SHA-256 hashes still verify and are flagged for upgrade', () {
      final old = _legacyHash('Cosmetix123');
      expect(PasswordHasher.verify('Cosmetix123', old), isTrue);
      expect(PasswordHasher.verify('wrong', old), isFalse);
      expect(PasswordHasher.needsUpgrade(old), isTrue);
    });

    test('an unusable hash never matches', () {
      expect(PasswordHasher.verify('', PasswordHasher.unusable), isFalse);
      expect(
        PasswordHasher.verify(PasswordHasher.unusable, PasswordHasher.unusable),
        isFalse,
      );
    });

    test('garbage hashes do not throw', () {
      expect(PasswordHasher.verify('x', 'pbkdf2\$abc'), isFalse);
      expect(PasswordHasher.verify('x', 'pbkdf2\$10\$!!\$!!'), isFalse);
    });
  });

  group('accounts', () {
    late DatabaseHelper helper;
    late UserRepository users;

    setUp(() async {
      helper = DatabaseHelper(path: inMemoryDatabasePath);
      users = UserRepository(helper);
      await helper.database;
    });
    tearDown(() => helper.close());

    test('a legacy hash is upgraded on login', () async {
      final db = await helper.database;
      await db.update('users', {
        'password_hash': _legacyHash(SeedData.demoPassword),
      }, where: 'id = 1');
      expect(await users.login(SeedData.demoEmail, 'nope'), isNull);
      expect(
        await users.login(SeedData.demoEmail, SeedData.demoPassword),
        isNotNull,
      );
      final stored =
          (await db.query('users', where: 'id = 1')).first['password_hash']
              as String;
      expect(stored, startsWith('pbkdf2\$'));
      expect(
        await users.login(SeedData.demoEmail, SeedData.demoPassword),
        isNotNull,
      );
    });

    test('social account has no usable password', () async {
      final u = await users.socialUser(
        provider: 'Google',
        email: 'google.user@cosmetix.local',
        firstName: 'Google',
        lastName: 'User',
      );
      expect(u, isNotNull);
      // the old guessable password and an empty one no longer work
      expect(
        await users.login('google.user@cosmetix.local', 'social-Google'),
        isNull,
      );
      expect(await users.login('google.user@cosmetix.local', ''), isNull);
      // signing in with Google again reuses the same account
      final again = await users.socialUser(
        provider: 'Google',
        email: 'google.user@cosmetix.local',
        firstName: 'Google',
        lastName: 'User',
      );
      expect(again!.id, u!.id);
    });

    test('social sign in refuses an ordinary password account', () async {
      await users.register(
        firstName: 'Eve',
        email: 'apple.user@cosmetix.local',
        password: 'Pass12345',
      );
      expect(
        await users.socialUser(
          provider: 'Apple',
          email: 'apple.user@cosmetix.local',
          firstName: 'Apple',
          lastName: 'User',
        ),
        isNull,
      );
    });

    test('a legacy social account (fixed password) is locked down', () async {
      final db = await helper.database;
      await users.register(
        firstName: 'Google',
        email: 'google.user@cosmetix.local',
        passwordHash: _legacyHash('social-Google'),
      );
      final u = await users.socialUser(
        provider: 'Google',
        email: 'google.user@cosmetix.local',
        firstName: 'Google',
        lastName: 'User',
      );
      expect(u, isNotNull);
      final stored = (await db.query(
        'users',
        where: 'email = ?',
        whereArgs: ['google.user@cosmetix.local'],
      )).first['password_hash'];
      expect(stored, PasswordHasher.unusable);
    });

    test('password reset needs the issued code', () async {
      final auth = AuthProvider(users);
      final code = await auth.requestResetCode(SeedData.demoEmail);
      expect(code, matches(RegExp(r'^\d{6}$')));
      expect(
        await auth.resetPassword(SeedData.demoEmail, '000000x', 'NewPass123'),
        isNotNull,
      );
      expect(await users.login(SeedData.demoEmail, 'NewPass123'), isNull);
      expect(
        await auth.resetPassword(SeedData.demoEmail, code, 'NewPass123'),
        isNull,
      );
      expect(await users.login(SeedData.demoEmail, 'NewPass123'), isNotNull);
      // the code is single use
      expect(
        await auth.resetPassword(SeedData.demoEmail, code, 'Another123'),
        isNotNull,
      );
    });

    test('reset code for an unknown email never works', () async {
      final auth = AuthProvider(users);
      final code = await auth.requestResetCode('nobody@mail.com');
      expect(
        code,
        matches(RegExp(r'^\d{6}$')),
      ); // same answer as for a real one
      expect(
        await auth.resetPassword('nobody@mail.com', code, 'NewPass123'),
        isNotNull,
      );
    });

    test('reset code is locked after too many wrong tries', () async {
      final auth = AuthProvider(users);
      final code = await auth.requestResetCode(SeedData.demoEmail);
      for (var i = 0; i < 5; i++) {
        await auth.resetPassword(SeedData.demoEmail, '000000', 'NewPass123');
      }
      expect(
        await auth.resetPassword(SeedData.demoEmail, code, 'NewPass123'),
        isNotNull,
      );
    });
  });

  group('bonus points', () {
    late DatabaseHelper helper;
    late UserRepository users;
    late CartRepository cart;

    setUp(() async {
      helper = DatabaseHelper(path: inMemoryDatabasePath);
      users = UserRepository(helper);
      cart = CartRepository(helper);
      await helper.database;
    });
    tearDown(() => helper.close());

    test('deleting an order takes its bonus back (no farming)', () async {
      await cart.add(1, 1, 1);
      final order = (await cart.checkout(1))!;
      expect((await users.getById(1))!.bonusPoints, order.bonus);
      await cart.deleteOrder(order.id);
      expect((await users.getById(1))!.bonusPoints, 0);
      expect(await cart.getOrders(1), isEmpty);
    });

    test('bonus never goes below zero when an old order is deleted', () async {
      await cart.add(1, 1, 1);
      final order = (await cart.checkout(1))!;
      await users.addBonus(1, -order.bonus - 5);
      await cart.deleteOrder(order.id);
      expect((await users.getById(1))!.bonusPoints, 0);
    });

    test(
      'points can be spent at checkout and are refunded on delete',
      () async {
        await users.addBonus(1, 500);
        await cart.add(1, 1, 1); // 3700
        final order = (await cart.checkout(1, useBonus: 500))!;
        expect(order.bonusSpent, 500);
        expect(order.total, 3700 - 500);
        expect(order.bonus, CartRepository.bonusFor(3200));
        // 500 - 500 spent + earned
        expect((await users.getById(1))!.bonusPoints, order.bonus);
        expect((await cart.getOrders(1)).single.bonusSpent, 500);

        await cart.deleteOrder(order.id);
        expect((await users.getById(1))!.bonusPoints, 500);
      },
    );

    test('cannot spend more than owned or the whole cart', () async {
      await users.addBonus(1, 100);
      await cart.add(1, 1, 1);
      final order = (await cart.checkout(1, useBonus: 99999))!;
      expect(order.bonusSpent, 100); // only what the user owns

      await users.addBonus(1, 1000000);
      await cart.add(1, 1, 1);
      final second = (await cart.checkout(1, useBonus: 99999))!;
      expect(second.total, 1); // at least 1 tenge is always paid
      expect(second.bonusSpent, 3699);
    });

    test('spendable helper', () {
      expect(CartRepository.spendable(0, 1000), 0);
      expect(CartRepository.spendable(300, 1000), 300);
      expect(CartRepository.spendable(5000, 1000), 999);
      expect(CartRepository.spendable(5000, 0), 0);
    });
  });

  group('saved photos', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('cosmetix_paths'));
    tearDown(() {
      AppPaths.setForTest();
      tmp.deleteSync(recursive: true);
    });

    test('toStored keeps only folder/file for our photo folders', () {
      expect(
        AppPaths.toStored('/var/app/Documents/avatars/a_1.jpg'),
        'avatars/a_1.jpg',
      );
      expect(
        AppPaths.toStored('/data/databases/review_photos/9.png'),
        'review_photos/9.png',
      );
      expect(AppPaths.toStored('/tmp/picker/x.jpg'), '/tmp/picker/x.jpg');
      expect(AppPaths.toStored(null), isNull);
    });

    test('a relative path is resolved under the current app folders', () {
      AppPaths.setForTest(documents: '/new/Documents', databases: '/new/db');
      expect(AppPaths.resolve('avatars/a.jpg'), '/new/Documents/avatars/a.jpg');
      expect(
        AppPaths.resolve('review_photos/r.jpg'),
        '/new/db/review_photos/r.jpg',
      );
      expect(AppPaths.resolve('/elsewhere/x.jpg'), '/elsewhere/x.jpg');
    });

    test('an old absolute path from another container is repaired', () {
      AppPaths.setForTest(documents: tmp.path, databases: tmp.path);
      expect(
        AppPaths.resolve('/old/container/Documents/avatars/a.jpg'),
        '${tmp.path}/avatars/a.jpg',
      );
      // a path that still exists is left alone
      Directory('${tmp.path}/avatars').createSync();
      final f = File('${tmp.path}/avatars/ok.jpg')..writeAsStringSync('x');
      expect(AppPaths.resolve(f.path), f.path);
    });

    test('deleting a review removes its photo file', () async {
      AppPaths.setForTest(documents: tmp.path, databases: tmp.path);
      Directory('${tmp.path}/review_photos').createSync();
      final photo = File('${tmp.path}/review_photos/p.jpg')
        ..writeAsStringSync('x');
      final helper = DatabaseHelper(path: inMemoryDatabasePath);
      addTearDown(helper.close);
      final reviews = ReviewRepository(helper);
      await reviews.add(
        productId: 1,
        userId: 1,
        author: 'A',
        rating: 5,
        body: 'text',
        photoPath: photo.path,
      );
      final r = (await reviews.forProduct(
        1,
      )).firstWhere((r) => r.photoPath != null);
      expect(r.photoPath, photo.path); // resolves back to the real file
      await reviews.delete(r.id);
      expect(photo.existsSync(), isFalse);
    });
  });

  group('demo reset', () {
    test('wipes user data and restores the demo set', () async {
      final helper = DatabaseHelper(path: inMemoryDatabasePath);
      addTearDown(helper.close);
      final users = UserRepository(helper);
      await users.register(
        firstName: 'Temp',
        email: 'temp@mail.com',
        password: 'Pass12345',
      );
      await helper.resetDemoData();
      expect(await users.emailExists('temp@mail.com'), isFalse);
      expect(
        await users.login(SeedData.demoEmail, SeedData.demoPassword),
        isNotNull,
      );
    });
  });

  group('AI address', () {
    test('a bare LAN IP gets the default Ollama port', () {
      const c = AiConfig(
        baseUrl: '192.168.1.50',
        textModel: '',
        visionModel: '',
      );
      expect(c.baseUri.toString(), 'http://192.168.1.50:11434');
      expect(c.displayHost, '192.168.1.50:11434');
    });

    test('explicit ports and host names are left alone', () {
      const a = AiConfig(
        baseUrl: '10.0.0.2:8080',
        textModel: '',
        visionModel: '',
      );
      expect(a.baseUri.toString(), 'http://10.0.0.2:8080');
      const b = AiConfig(
        baseUrl: 'ollama.local',
        textModel: '',
        visionModel: '',
      );
      expect(b.baseUri.toString(), 'http://ollama.local');
    });
  });
}
