import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/core/utils/app_paths.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/database/seed_data.dart';
import 'package:cosmetix/repositories/user_repository.dart';
import 'package:cosmetix/services/avatar_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('cosmetix_mig'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// An existing install: schema version 3 (the previous release) with data.
  Future<String> makeV3Database({bool withoutReviewPhoto = false}) async {
    final path = '${tmp.path}/old.db';
    final db = await openDatabase(
      path,
      version: withoutReviewPhoto ? 2 : 3, // v2 = older build
      onCreate: (db, _) async {
        for (final sql in DatabaseHelper.schemaV3) {
          if (withoutReviewPhoto && sql.contains('CREATE TABLE reviews')) {
            await db.execute('''
CREATE TABLE reviews (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
  author TEXT NOT NULL, rating INTEGER NOT NULL, body TEXT NOT NULL,
  created_at INTEGER NOT NULL)''');
          } else {
            await db.execute(sql);
          }
        }
        await db.insert('users', {
          'id': 7,
          'first_name': 'Мария',
          'last_name': 'Тест',
          'email': 'maria@test.kz',
          'password_hash': 'hash',
          'skin_type': 'Сухая',
          'skin_tone': 'Светлый',
          'undertone': 'Холодный',
          'color_type': 'Лето',
          'skin_concerns': 'Пигментация',
          'bonus_points': 120,
          'created_at': 1,
          'updated_at': 1,
        });
        await db.insert('products', {
          'id': 5,
          'brand': 'Anua',
          'name': 'Тонер Heartleaf 77%', // has curated traits in the seed
          'category': 'Уход за лицом',
          'price': 6300,
          'color': 0xFFB9D9B0,
          'created_at': 1,
        });
        await db.insert('products', {
          'id': 6,
          'brand': 'Мой бренд',
          'name': 'Мой товар',
          'category': 'Макияж',
          'price': 100,
          'color': 0,
          'created_at': 1,
        });
        await db.insert('favorites', {
          'user_id': 7,
          'product_id': 5,
          'created_at': 1,
        });
        await db.insert('blacklist', {
          'user_id': 7,
          'name': 'Парабены',
          'group_key': 'paraben',
          'enabled': 1,
          'is_custom': 0,
        });
        await db.insert('reviews', {
          'product_id': 5,
          'user_id': 7,
          'author': 'Мария',
          'rating': 5,
          'body': 'Очень понравилось, спасибо',
          'created_at': 1,
        });
      },
    );
    await db.close();
    return path;
  }

  test('upgrade 3 -> 4 keeps all user data', () async {
    final path = await makeV3Database();
    final helper = DatabaseHelper(path: path);
    final db = await helper.database;
    addTearDown(helper.close);

    final user = (await db.query('users', where: 'id = 7')).single;
    expect(user['first_name'], 'Мария');
    expect(user['email'], 'maria@test.kz');
    expect(user['color_type'], 'Лето');
    expect(user['bonus_points'], 120);
    expect(user['avatar_path'], isNull); // new column, empty
    expect(user['beauty_source'], 'questionnaire');

    expect((await db.query('favorites')).length, 1);
    expect((await db.query('blacklist')).single['name'], 'Парабены');
    expect((await db.query('reviews')).single['body'], contains('понравилось'));
    // custom user product survives (the old strategy dropped everything)
    expect(
      (await db.query('products', where: 'id = 6')).single['name'],
      'Мой товар',
    );
    // the two products of the old database + the four catalog products that
    // the later migration adds (they never replace a user's product)
    expect((await db.query('products')).length, 2 + 4);
    expect(
      (await db.query('products', where: 'id = 19')).single['brand'],
      'The Ordinary',
    );
  });

  test('upgrade adds orders.bonus_spent with a zero default', () async {
    final path = await makeV3Database();
    final helper = DatabaseHelper(path: path);
    final db = await helper.database;
    addTearDown(helper.close);

    final cols = await db.rawQuery('PRAGMA table_info(orders)');
    expect(cols.any((c) => c['name'] == 'bonus_spent'), isTrue);
    await db.insert('orders', {'user_id': 7, 'total': 1000, 'created_at': 1});
    expect((await db.query('orders')).single['bonus_spent'], 0);
  });

  test('upgrade adds the new tables and backfills curated traits', () async {
    final path = await makeV3Database();
    final helper = DatabaseHelper(path: path);
    final db = await helper.database;
    addTearDown(helper.close);

    for (final t in [
      'product_skin_types',
      'product_color_types',
      'product_undertones',
      'product_concerns',
      'product_tags',
      'product_ai_classification',
    ]) {
      expect(await db.query(t, limit: 1), isA<List>(), reason: t);
    }
    final skin = await db.query('product_skin_types', where: 'product_id = 5');
    expect(skin.map((r) => r['skin_type']), containsAll(['oily', 'sensitive']));
    // the user's own product has no curated traits and is left alone
    expect(
      await db.query('product_skin_types', where: 'product_id = 6'),
      isEmpty,
    );
    expect(
      (await db.rawQuery('PRAGMA foreign_keys')).single['foreign_keys'],
      1,
    );
  });

  test(
    'a database from an older build without reviews.photo_path upgrades',
    () async {
      final path = await makeV3Database(withoutReviewPhoto: true);
      final db = await DatabaseHelper(path: path).database;
      final cols = (await db.rawQuery(
        'PRAGMA table_info(reviews)',
      )).map((r) => r['name']);
      expect(cols, contains('photo_path'));
      expect((await db.query('reviews')).length, 1);
      await db.close();
    },
  );

  test('a fresh install has the same schema as an upgraded one', () async {
    final fresh = DatabaseHelper(path: inMemoryDatabasePath);
    addTearDown(fresh.close);
    final path = await makeV3Database();
    final upgraded = DatabaseHelper(path: path);
    addTearDown(upgraded.close);

    Future<Set<String>> columns(DatabaseHelper h) async {
      final db = await h.database;
      final out = <String>{};
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      );
      for (final t in tables) {
        for (final c in await db.rawQuery('PRAGMA table_info(${t['name']})')) {
          out.add('${t['name']}.${c['name']}');
        }
      }
      return out;
    }

    expect(await columns(upgraded), await columns(fresh));
  });

  group('avatar', () {
    test('avatar_path is persisted in SQLite and can be cleared', () async {
      final helper = DatabaseHelper(path: '${tmp.path}/avatar.db');
      final users = UserRepository(helper);
      final id = (await users.register(
        firstName: 'Ая',
        email: 'aya@test.kz',
        password: 'Passw0rd1',
      )).id;
      expect((await users.getById(id))!.avatarPath, isNull);
      AppPaths.setForTest(documents: '/data');
      addTearDown(AppPaths.setForTest);
      await users.setAvatarPath(id, '/data/avatars/a.jpg');
      // saved relative to the app folder, so it survives a changed container
      final db = await helper.database;
      expect(
        (await db.query(
          'users',
          where: 'id = ?',
          whereArgs: [id],
        )).single['avatar_path'],
        'avatars/a.jpg',
      );
      await helper.close();

      // a new connection (app restart) still sees it
      final again = UserRepository(
        DatabaseHelper(path: '${tmp.path}/avatar.db'),
      );
      expect((await again.getById(id))!.avatarPath, '/data/avatars/a.jpg');
      await again.setAvatarPath(id, null);
      expect((await again.getById(id))!.avatarPath, isNull);
    });

    test('AvatarService copies the picked photo into documents', () async {
      final docs = Directory('${tmp.path}/docs')..createSync();
      final picked = File('${tmp.path}/cache_pick.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      final service = AvatarService(documentsDir: () async => docs);
      final stored = await service.store(picked, 7);
      expect(stored, startsWith('${docs.path}/avatars/avatar_7_'));
      expect(File(stored).readAsBytesSync(), [1, 2, 3]);
      // the stored file does not depend on the picker's cache file
      picked.deleteSync();
      expect(File(stored).existsSync(), isTrue);
      await service.delete(stored);
      expect(File(stored).existsSync(), isFalse);
    });
  });

  group('real catalog (DB v7)', () {
    test('old demo products become real ones, other products stay', () async {
      final helper = DatabaseHelper(path: inMemoryDatabasePath);
      addTearDown(helper.close);
      final db = await helper.database;
      // what an install of the previous release looks like
      await db.update('products', {
        'brand': 'Flower Knows',
        'name': 'Палетка Flower Knows Strawberry',
        'art': 'palette',
        'inci': '',
        'source_url': '',
      }, where: 'id = 1');
      await db.insert('products', {
        'id': 99,
        'brand': 'My shop',
        'name': 'Мой товар',
        'category': 'Макияж',
        'price': 1000,
        'color': 0xFFFFFFFF,
        'created_at': 0,
      });
      await SeedData.applyRealCatalog(db);

      final p1 = (await db.query('products', where: 'id = 1')).single;
      expect(p1['brand'], '3CE');
      expect(p1['name'], 'Super Slim Waterproof Mascara');
      expect(p1['art'], 'tube|assets/products/1.jpg');
      expect(p1['inci'] as String, contains('Isododecane'));
      expect(
        p1['source_url'] as String,
        startsWith('https://incidecoder.com/'),
      );
      final p99 = (await db.query('products', where: 'id = 99')).single;
      expect(p99['name'], 'Мой товар');
      // the demo user's favourites still point at the same ids
      expect(await db.query('favorites', where: 'product_id = 1'), isNotEmpty);
      // running it again changes nothing
      await SeedData.applyRealCatalog(db);
      expect(
        (await db.query('products', where: 'id = 1')).single['name'],
        'Super Slim Waterproof Mascara',
      );
    });

    test(
      'every catalog product has a photo file and a published INCI list',
      () async {
        final helper = DatabaseHelper(path: inMemoryDatabasePath);
        addTearDown(helper.close);
        final db = await helper.database;
        final rows = await db.query('products');
        var real = 0;
        for (final r in rows) {
          final inci = r['inci'] as String;
          if (inci.isEmpty) continue; // the Cosmetix gift set
          real++;
          final art = (r['art'] as String).split('|');
          expect(art.length, 2, reason: r['name'] as String);
          expect(File(art[1]).existsSync(), isTrue, reason: art[1]);
          expect(r['source_url'] as String, startsWith('https://'));
        }
        expect(real, 21);
      },
    );
  });
}
