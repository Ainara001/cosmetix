import 'package:sqflite/sqflite.dart';

/// TEST FIXTURE: turns the demo rows of `product_prices` into VERIFIED
/// `store_offers`, so the tests of the cart and of the shop screens still have
/// shop prices to work with. It is not data of the app: a real install has no
/// verified offer until a person enters one.
Future<void> verifyDemoOffers(DatabaseExecutor db) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  final batch = db.batch();
  for (final r in await db.query('product_prices')) {
    final qty = r['qty'] as int?;
    final out = (r['in_stock'] as int? ?? 1) == 0 || qty == 0;
    batch.insert('store_offers', {
      'product_id': r['product_id'],
      'store_id': r['store_id'],
      'price': r['price'],
      'availability': out ? 'out_of_stock' : 'in_stock',
      'url_kind': 'none',
      'source': 'test fixture: copy of the demo offers',
      'method': 'import_file',
      'verification': 'verified',
      'checked_at': now,
    });
  }
  await batch.commit(noResult: true);
}
