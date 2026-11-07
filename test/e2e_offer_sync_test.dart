import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/core/theme/app_theme.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/models/store_offer.dart';
import 'package:cosmetix/repositories/offer_repository.dart';
import 'package:cosmetix/repositories/offer_sync_repository.dart';
import 'package:cosmetix/repositories/product_repository.dart';
import 'package:cosmetix/services/ai/ai_config.dart';
import 'package:cosmetix/services/offer_sync_service.dart';
import 'package:cosmetix/services/server/server_http.dart';
import 'package:cosmetix/services/source_policy.dart';
import 'package:cosmetix/widgets/offer_widgets.dart';

/// One step of the real end-to-end scenario (PostgreSQL -> server API -> app ->
/// SQLite -> price card -> link). It is driven by `tool/e2e_offer_sync.sh`, which
/// starts a throw-away PostgreSQL schema and the real server, changes the offer
/// through the admin API between the steps and runs this file once per step with
/// the same database FILE (so the "offline" step really shows the last copy).
///
/// Skipped unless E2E_SERVER is set. The offer used is TEST DATA ("TEST DATA"
/// in its source) and never mixes with commercial data: the database is a
/// temporary file and the PostgreSQL schema is dropped afterwards.
///
/// E2E_EXPECT_SYNC  ok | fail
/// E2E_EXPECT_PRICE a number, or none (no offer for the product)
/// E2E_EXPECT_OLD   old price (optional)
/// E2E_EXPECT_LINK  1: the "view in the shop" button opens the stored address
void main() {
  final server = Platform.environment['E2E_SERVER'];
  final dbPath = Platform.environment['E2E_DB'] ?? '';
  // skipped unless run by tool/e2e_offer_sync.sh
  final skip = server == null || dbPath.isEmpty;
  const productId = 12; // The Ordinary Niacinamide 10% + Zinc 1%
  const storeId = 2; // Золотое Яблоко, пр. Кабанбай батыра, 62

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final saved = DatabaseHelper.afterSeed;
  setUp(() => DatabaseHelper.afterSeed = null);
  tearDown(() => DatabaseHelper.afterSeed = saved);

  Future<List<StoreOffer>> syncAndRead() async {
    // the widget binding of the second test blocks real HTTP: this step needs it
    HttpOverrides.global = null;
    final h = DatabaseHelper(path: dbPath);
    try {
      final repo = OfferSyncRepository(h);
      final cfg = AiConfig(baseUrl: server!);
      final r = await OfferSyncService(
        ServerHttp(
          () => cfg,
          retry: RetryPolicy.none,
          timeout: const Duration(seconds: 5),
        ),
        repo,
        configured: () => cfg.isConfigured,
      ).sync();
      final want = Platform.environment['E2E_EXPECT_SYNC'] ?? 'ok';
      expect(r.ok ? 'ok' : 'fail', want, reason: 'sync result: ${r.error}');
      // never a duplicate: one row per product and shop
      final db = await h.database;
      final dup = await db.rawQuery(
        'SELECT product_id, store_id, COUNT(*) c FROM store_offers '
        'GROUP BY product_id, store_id HAVING c > 1',
      );
      expect(dup, isEmpty);
      // what a price card shows: only verified offers
      return await OfferRepository(h).forProduct(productId);
    } finally {
      await h.close();
    }
  }

  test('E2E step: sync and check what the price card would show', () async {
    final offers = await syncAndRead();
    final want = Platform.environment['E2E_EXPECT_PRICE'] ?? 'none';
    if (want == 'none') {
      expect(offers, isEmpty);
    } else {
      expect(offers, hasLength(1));
      expect(offers.single.price, int.parse(want));
      expect(offers.single.storeId, storeId);
      expect(offers.single.source, startsWith('TEST DATA'));
      final old = Platform.environment['E2E_EXPECT_OLD'];
      if (old != null && old.isNotEmpty) expect(offers.single.oldPrice, int.parse(old));
      // the date the person checked it is kept: shown as "checked <date>"
      expect(offers.single.checkedAt, isNotNull);
    }
    final h = DatabaseHelper(path: dbPath);
    addTearDown(h.close);
    final at = await OfferSyncRepository(h).lastSyncedAt();
    // ignore: avoid_print
    print(
      'E2E ${Platform.environment['E2E_STEP']}: offers=${offers.length} '
      'price=${offers.isEmpty ? '-' : offers.single.price} lastSync=$at',
      // the sync date stays after a failed sync (offline shows the old copy)
    );
    if (Platform.environment['E2E_EXPECT_SYNC'] == 'fail') {
      expect(at, isNotNull, reason: 'the last good copy keeps its date');
    }
  }, skip: skip);

  testWidgets('E2E step: the link opens the address the admin stored', (
    t,
  ) async {
    if (Platform.environment['E2E_EXPECT_LINK'] != '1') return;
    final h = DatabaseHelper(path: dbPath);
    final prices = await t.runAsync(
      () => ProductRepository(h).getStorePrices(productId),
    );
    await t.runAsync(h.close);
    final p = prices!.singleWhere((e) => e.storeId == storeId);
    expect(p.url, isNotNull);
    Uri? opened;
    OfferLink.launcher = (u) async {
      opened = u;
      return true;
    };
    // TEST policy: the real policy allows no shop. This only proves the chain
    // "stored address -> button -> launcher"; it is not a permission.
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: OfferLink(
            offer: p,
            policy: const SourcePolicy.of({'Золотое Яблоко': 'allowed'}),
          ),
        ),
      ),
    );
    await t.tap(find.byType(TextButton));
    expect(opened.toString(), p.url);
    // and with the real (bundled) policy no link is offered
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: OfferLink(offer: p)),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byType(TextButton), findsNothing);
  }, skip: skip);
}
