import 'package:sqflite/sqflite.dart';

import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/models/store_offer.dart';

/// What a person (or a feed that the shop's conditions allow) checked about one
/// product in one shop. Validated before it is written: nothing is filled in
/// by default and an unknown price or stock stays unknown.
class OfferInput {
  const OfferInput({
    required this.productId,
    required this.storeId,
    required this.source,
    required this.method,
    required this.checkedAt,
    this.city = 'Астана',
    this.price,
    this.oldPrice,
    this.availability = Availability.unknown,
    this.url,
    this.urlKind = UrlKind.none,
    this.volumeText,
    this.variantText,
    this.checkedBy,
    this.note,
    this.verified = true,
  });

  final int productId;
  final int storeId;
  final String city;
  final int? price;
  final int? oldPrice;
  final Availability availability;
  final String? url;
  final UrlKind urlKind;
  final String? volumeText;
  final String? variantText;

  /// Where the information comes from ("shelf price, shop on Sarykarka 15").
  final String source;
  final String method;
  final DateTime checkedAt;
  final String? checkedBy;
  final String? note;

  /// `verified` offers are shown to users; the others wait for a check.
  final bool verified;

  /// Throws a [FormatException] saying what is wrong.
  void validate() {
    Never bad(String why) => throw FormatException('offer: $why');
    if (source.trim().isEmpty) {
      bad('the source of the information is required');
    }
    if (!OfferMethod.all.contains(method)) bad('unknown method "$method"');
    if (price != null && price! <= 0) {
      bad('the price must be above zero');
    }
    if (oldPrice != null && oldPrice! <= 0) {
      bad('the old price must be above zero');
    }
    if (oldPrice != null && (price == null || oldPrice! <= price!)) {
      bad('the old price must be above the price');
    }
    if (urlKind != UrlKind.none && url == null) {
      bad('a link kind needs the link');
    }
    if (url != null) {
      final u = Uri.tryParse(url!);
      if (u == null ||
          !(u.scheme == 'https' || u.scheme == 'http') ||
          !u.hasAuthority) {
        bad('the link must be an http(s) address');
      }
      if (urlKind == UrlKind.none) {
        bad('say whether the link opens the product or a search');
      }
    }
    if (checkedAt.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
      bad('the check time is in the future');
    }
    if (verified &&
        price == null &&
        availability == Availability.unknown &&
        urlKind != UrlKind.product) {
      bad('a verified offer must say a price, a stock or give a product link');
    }
  }
}

/// Reads and writes the verified shop offers (DB v17 `store_offers`).
class OfferRepository {
  const OfferRepository(this._helper);

  final DatabaseHelper _helper;

  static const _select = '''
SELECT o.*, s.name AS store_name, s.chain AS chain
FROM store_offers o JOIN stores s ON s.id = o.store_id''';

  /// Offers of a product, verified ones first, cheapest first.
  Future<List<StoreOffer>> forProduct(
    int productId, {
    bool onlyVerified = true,
  }) async {
    final db = await _helper.database;
    final rows = await db.rawQuery(
      '$_select WHERE o.product_id = ? '
      '${onlyVerified ? "AND o.verification = 'verified' " : ''}'
      'ORDER BY (o.verification = \'verified\') DESC, '
      'o.price IS NULL, o.price',
      [productId],
    );
    return rows.map(StoreOffer.fromMap).toList();
  }

  /// Adds or replaces the offer of this product in this shop. Returns its id.
  Future<int> save(OfferInput o) async {
    o.validate();
    final db = await _helper.database;
    return db.insert('store_offers', {
      'product_id': o.productId,
      'store_id': o.storeId,
      'city': o.city,
      'price': o.price,
      'old_price': o.oldPrice,
      'availability': o.availability.code,
      'url': o.url,
      'url_kind': o.urlKind.code,
      'volume_text': o.volumeText,
      'variant_text': o.variantText,
      'source': o.source.trim(),
      'method': o.method,
      'verification': o.verified ? 'verified' : 'unverified',
      'checked_at': o.checkedAt.millisecondsSinceEpoch,
      'checked_by': o.checkedBy,
      'note': o.note,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> remove(int productId, int storeId) async {
    final db = await _helper.database;
    await db.delete(
      'store_offers',
      where: 'product_id = ? AND store_id = ?',
      whereArgs: [productId, storeId],
    );
  }
}
