import 'package:sqflite/sqflite.dart';

import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/models/server_offer.dart';

/// What one snapshot did to the local copy.
class SnapshotApplied {
  const SnapshotApplied({
    required this.stored,
    required this.skippedUnknownProduct,
    required this.skippedUnknownStore,
    required this.skippedInvalid,
    required this.skippedConflict,
  });

  final int stored;
  final int skippedUnknownProduct;
  final int skippedUnknownStore;
  final int skippedInvalid;
  final int skippedConflict;

  int get skipped =>
      skippedUnknownProduct +
      skippedUnknownStore +
      skippedInvalid +
      skippedConflict;
}

/// Writes the server's snapshot of verified offers into SQLite.
///
/// The snapshot REPLACES the earlier one (`origin = 'server'`) in a single
/// transaction: an offer that was withdrawn, unverified or changed on the
/// server is gone or updated, a repeated sync cannot make duplicates, and a
/// failure in the middle leaves the old copy as it was. Offers entered on the
/// phone (`origin = 'local'`) are never touched, and nothing of the user's data
/// (favourites, cart, orders, reviews, settings) is read or written here.
class OfferSyncRepository {
  const OfferSyncRepository(this._helper);

  final DatabaseHelper _helper;

  Future<SnapshotApplied> apply(
    List<ServerOffer> offers, {
    DateTime? now,
  }) async {
    final db = await _helper.database;
    final at = (now ?? DateTime.now()).millisecondsSinceEpoch;
    return db.transaction((txn) async {
      final products = {
        for (final r in await txn.query('products', columns: ['id', 'brand', 'name']))
          '${r['brand']}|${r['name']}': r['id']! as int,
      };
      final stores = {
        for (final r in await txn.query('stores', columns: ['id', 'name', 'address']))
          '${r['name']}|${r['address']}': r['id']! as int,
      };
      await txn.delete('store_offers', where: "origin = 'server'");
      var stored = 0, noProduct = 0, noStore = 0, invalid = 0, conflict = 0;
      for (final o in offers) {
        final productId = products['${o.brand}|${o.productName}'];
        if (productId == null) {
          noProduct++;
          continue;
        }
        final storeId = stores['${o.storeName}|${o.storeAddress}'];
        if (storeId == null) {
          noStore++;
          continue;
        }
        final taken = await txn.query(
          'store_offers',
          columns: ['id'],
          where: 'product_id = ? AND store_id = ?',
          whereArgs: [productId, storeId],
        );
        if (taken.isNotEmpty) {
          conflict++; // an offer entered on the phone wins
          continue;
        }
        try {
          await txn.insert('store_offers', {
            'product_id': productId,
            'store_id': storeId,
            'city': o.city.isEmpty ? 'Астана' : o.city,
            'price': o.price,
            'old_price': o.oldPrice,
            'availability': o.availability.code,
            'url': o.url,
            'url_kind': o.url == null ? 'none' : o.urlKind.code,
            'source': o.source,
            'method': o.method,
            'verification': 'verified',
            'checked_at': o.checkedAt,
            'origin': 'server',
            'synced_at': at,
          });
          stored++;
        } catch (_) {
          // a row the database refuses (a price of 0, a bad link): not stored,
          // the rest of the snapshot still is
          invalid++;
        }
      }
      return SnapshotApplied(
        stored: stored,
        skippedUnknownProduct: noProduct,
        skippedUnknownStore: noStore,
        skippedInvalid: invalid,
        skippedConflict: conflict,
      );
    });
  }

  /// When the last good snapshot was copied (null: never).
  static const keySyncedAt = 'offers_synced_at';
  static const keyError = 'offers_sync_error';
  static const keyErrorAt = 'offers_sync_error_at';

  Future<DateTime?> lastSyncedAt() async {
    final db = await _helper.database;
    final r = await db.query('settings', where: 'key = ?', whereArgs: [keySyncedAt]);
    final v = r.isEmpty ? null : int.tryParse('${r.first['value']}');
    return v == null ? null : DateTime.fromMillisecondsSinceEpoch(v);
  }

  Future<void> remember(String key, String value) async {
    final db = await _helper.database;
    await db.insert('settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> forget(String key) async {
    final db = await _helper.database;
    await db.delete('settings', where: 'key = ?', whereArgs: [key]);
  }
}
