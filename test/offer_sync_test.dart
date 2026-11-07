import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/models/store_offer.dart';
import 'package:cosmetix/providers/offer_sync_provider.dart';
import 'package:cosmetix/repositories/offer_repository.dart';
import 'package:cosmetix/repositories/offer_sync_repository.dart';
import 'package:cosmetix/services/ai/ai_config.dart';
import 'package:cosmetix/services/offer_sync_service.dart';
import 'package:cosmetix/services/server/server_http.dart';

/// The copy of the server's verified offers in SQLite: replaced as a whole,
/// without duplicates, withdrawn offers disappear, a failed sync changes
/// nothing, and the user's own data is not touched. The "server" here is a
/// local fake and every offer is TEST DATA (never real commercial data).
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final saved = DatabaseHelper.afterSeed;
  setUp(() => DatabaseHelper.afterSeed = null);
  tearDown(() => DatabaseHelper.afterSeed = saved);

  late DatabaseHelper h;
  late HttpServer server;
  late String productBrand, productName, storeName, storeAddress;
  late int productId, storeId;
  // what the fake server answers with
  Object? body;
  int status = 200;
  var requests = 0;
  Map<String, String> lastHeaders = {};

  Map<String, Object?> offerJson({
    int? price = 5600,
    int? oldPrice,
    String? url,
    String urlKind = 'none',
    String availability = 'in_stock',
    String? brand,
    String? name,
  }) => {
    'brand': brand ?? productBrand,
    'productName': name ?? productName,
    'storeName': storeName,
    'storeAddress': storeAddress,
    'city': 'Астана',
    'price': price,
    'oldPrice': oldPrice,
    'availability': availability,
    'url': url,
    'urlKind': urlKind,
    'source': 'TEST DATA: not a real price',
    'method': 'manual_visit',
    'verification': 'verified',
    'checkedAt': DateTime.now().toUtc().toIso8601String(),
  };

  Object snapshot(List<Map<String, Object?>> items) => {
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'items': items,
  };

  OfferSyncService serviceFor(AiConfig cfg, OfferSyncRepository repo) =>
      OfferSyncService(
        ServerHttp(
          () => cfg,
          retry: RetryPolicy.none,
          timeout: const Duration(seconds: 3),
        ),
        repo,
        configured: () => cfg.isConfigured,
      );

  late OfferSyncRepository repo;
  late OfferSyncService service;

  setUp(() async {
    h = DatabaseHelper(path: inMemoryDatabasePath);
    final db = await h.database;
    final p = (await db.query('products', where: 'id = 12')).single;
    productId = 12;
    productBrand = p['brand']! as String;
    productName = p['name']! as String;
    final s = (await db.query('stores', where: 'id = 2')).single;
    storeId = 2;
    storeName = s['name']! as String;
    storeAddress = s['address']! as String;

    body = snapshot([]);
    status = 200;
    requests = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      requests++;
      lastHeaders = {};
      req.headers.forEach((k, v) => lastHeaders[k] = v.join(','));
      expect(req.method, 'GET');
      expect(req.uri.path, '/v1/catalog/offers');
      req.response.statusCode = status;
      req.response.headers.contentType = ContentType.json;
      req.response.write(body is String ? body : jsonEncode(body));
      await req.response.close();
    });
    repo = OfferSyncRepository(h);
    service = serviceFor(
      AiConfig(baseUrl: 'http://127.0.0.1:${server.port}'),
      repo,
    );
  });

  tearDown(() async {
    await server.close(force: true);
    await h.close();
  });

  Future<List<Map<String, Object?>>> rows() async =>
      (await h.database).query('store_offers');

  test('a fresh install has no offers; a snapshot fills them in', () async {
    expect(await rows(), isEmpty);
    body = snapshot([offerJson(price: 5600, oldPrice: 7000)]);
    final r = await service.sync();
    expect(r.ok, isTrue);
    expect(r.applied!.stored, 1);
    final offers = await OfferRepository(h).forProduct(productId);
    expect(offers.single.price, 5600);
    expect(offers.single.oldPrice, 7000);
    expect(offers.single.isVerified, isTrue);
    final row = (await rows()).single;
    expect(row['origin'], 'server');
    expect(row['synced_at'], isNotNull);
    expect(await repo.lastSyncedAt(), isNotNull);
  });

  test('the request carries nothing about the user', () async {
    await service.sync();
    expect(requests, 1);
    expect(lastHeaders['user-agent'], 'cosmetix-app');
    expect(lastHeaders.containsKey('authorization'), isFalse);
    expect(lastHeaders.containsKey('cookie'), isFalse);
  });

  test('a repeated sync does not duplicate; a new price replaces the old', () async {
    body = snapshot([offerJson(price: 5600)]);
    await service.sync();
    await service.sync();
    expect(await rows(), hasLength(1));
    body = snapshot([offerJson(price: 4900)]);
    await service.sync();
    final all = await OfferRepository(h).forProduct(productId);
    expect(all, hasLength(1));
    expect(all.single.price, 4900);
  });

  test('an offer withdrawn on the server disappears from the app', () async {
    body = snapshot([offerJson()]);
    await service.sync();
    expect(await rows(), hasLength(1));
    body = snapshot([]); // revoked / unverified / deleted on the server
    final r = await service.sync();
    expect(r.ok, isTrue);
    expect(await rows(), isEmpty);
    expect(await OfferRepository(h).forProduct(productId), isEmpty);
  });

  test('an unconfirmed price (null) and the link kind are kept as sent', () async {
    body = snapshot([
      offerJson(
        price: null,
        url: 'https://shop.example/p/1',
        urlKind: 'product',
        availability: 'unknown',
      ),
    ]);
    await service.sync();
    final row = (await rows()).single;
    expect(row['price'], isNull);
    expect(row['availability'], 'unknown');
    expect(row['url_kind'], 'product');
  });

  test('no network: nothing is changed, the old snapshot keeps its date', () async {
    body = snapshot([offerJson(price: 5600)]);
    await service.sync();
    final before = await repo.lastSyncedAt();
    await server.close(force: true);
    final r = await service.sync();
    expect(r.ok, isFalse);
    expect(r.error, isNotNull);
    final all = await OfferRepository(h).forProduct(productId);
    expect(all.single.price, 5600);
    expect(await repo.lastSyncedAt(), before);
  });

  test('a server error (500) or a malformed answer changes nothing', () async {
    body = snapshot([offerJson(price: 5600)]);
    await service.sync();
    status = 500;
    body = {'message': 'boom'};
    expect((await service.sync()).ok, isFalse);
    status = 200;
    body = 'this is not json';
    expect((await service.sync()).ok, isFalse);
    // one bad row spoils the whole snapshot: nothing is applied
    body = snapshot([offerJson(price: 1), offerJson(price: -5)]);
    expect((await service.sync()).ok, isFalse);
    body = snapshot([offerJson(price: 0)]);
    expect((await service.sync()).ok, isFalse);
    final all = await OfferRepository(h).forProduct(productId);
    expect(all.single.price, 5600);
  });

  test('an offer for a product or a shop the app does not know is skipped and counted', () async {
    body = snapshot([
      offerJson(brand: 'No Such Brand', name: 'No Such Product'),
      {...offerJson(), 'storeName': 'Unknown shop'},
      offerJson(price: 5000),
    ]);
    final r = await service.sync();
    expect(r.applied!.stored, 1);
    expect(r.applied!.skippedUnknownProduct, 1);
    expect(r.applied!.skippedUnknownStore, 1);
  });

  test('an offer entered on the phone is never touched by a sync', () async {
    await OfferRepository(h).save(
      OfferInput(
        productId: productId,
        storeId: storeId,
        price: 3000,
        availability: Availability.inStock,
        urlKind: UrlKind.none,
        source: 'TEST DATA: entered on the phone',
        method: OfferMethod.manualVisit,
        checkedAt: DateTime.now(),
        verified: true,
      ),
    );
    body = snapshot([offerJson(price: 9999)]);
    final r = await service.sync();
    expect(r.applied!.skippedConflict, 1);
    final row = (await rows()).single;
    expect(row['price'], 3000);
    expect(row['origin'], 'local');
    // and an empty snapshot does not delete it
    body = snapshot([]);
    await service.sync();
    expect(await rows(), hasLength(1));
  });

  test('without a server address nothing is requested', () async {
    final s = serviceFor(const AiConfig(baseUrl: ''), repo);
    final r = await s.sync();
    expect(r.notConfigured, isTrue);
    expect(requests, 0);
  });

  test('the user data and the settings are not touched', () async {
    final db = await h.database;
    await db.insert('settings', {'key': 'language', 'value': 'kk'});
    final tablesBefore = {
      for (final t in ['users', 'cart_items', 'favorites', 'reviews'])
        t: (await db.query(t)).length,
    };
    body = snapshot([offerJson()]);
    await service.sync();
    body = snapshot([]);
    await service.sync();
    expect(
      (await db.query('settings', where: "key = 'language'")).single['value'],
      'kk',
    );
    for (final e in tablesBefore.entries) {
      expect((await db.query(e.key)).length, e.value, reason: e.key);
    }
  });

  test('the provider reports the state and tells the catalog to reload', () async {
    body = snapshot([offerJson()]);
    final p = OfferSyncProvider(service, repo, configured: () => true);
    var reloaded = 0;
    p.onApplied = () => reloaded++;
    await p.load();
    expect(p.lastSyncedAt, isNull);
    await p.sync();
    expect(p.lastSyncedAt, isNotNull);
    expect(p.error, isNull);
    expect(reloaded, 1);
    await server.close(force: true);
    await p.sync();
    expect(p.error, isNotNull);
    expect(reloaded, 1, reason: 'no reload when nothing changed');
    expect(p.lastSyncedAt, isNotNull, reason: 'the last good date stays');
  });

  test('a v17 database is migrated to v18 with its offers kept as local', () async {
    final dir = await Directory.systemTemp.createTemp('cx_mig');
    final path = '${dir.path}/c.db';
    addTearDown(() => dir.delete(recursive: true));
    final a = DatabaseHelper(path: path);
    final db = await a.database;
    await OfferRepository(a).save(
      OfferInput(
        productId: productId,
        storeId: storeId,
        price: 3000,
        availability: Availability.inStock,
        urlKind: UrlKind.none,
        source: 'TEST DATA',
        method: OfferMethod.manualVisit,
        checkedAt: DateTime.now(),
        verified: true,
      ),
    );
    // make it look like a v17 file
    await db.execute('ALTER TABLE store_offers DROP COLUMN origin');
    await db.execute('ALTER TABLE store_offers DROP COLUMN synced_at');
    await db.execute('PRAGMA user_version = 17');
    await a.close();

    final b = DatabaseHelper(path: path);
    final db2 = await b.database;
    final cols = (await db2.rawQuery('PRAGMA table_info(store_offers)'))
        .map((c) => c['name'])
        .toSet();
    expect(cols, containsAll(['origin', 'synced_at']));
    final row = (await db2.query('store_offers')).single;
    expect(row['origin'], 'local');
    expect(row['price'], 3000);
    expect(
      (await db2.rawQuery('PRAGMA user_version')).single.values.single,
      DatabaseHelper.dbVersion,
    );
    await b.close();
  });
}
