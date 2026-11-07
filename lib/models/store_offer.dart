/// How a person or a feed obtained an offer.
abstract final class OfferMethod {
  static const manualVisit = 'manual_visit'; // looked at in the shop
  static const manualSite = 'manual_site'; // looked at on the shop's site
  static const partnerFeed = 'partner_feed';
  static const officialApi = 'official_api';
  static const importFile = 'import_file';
  static const all = {
    manualVisit,
    manualSite,
    partnerFeed,
    officialApi,
    importFile,
  };
}

/// Stock of a product in a shop: only `inStock` / `outOfStock` after a real
/// check, otherwise `unknown`. "Unknown" is not "out of stock".
enum Availability {
  inStock('in_stock'),
  outOfStock('out_of_stock'),
  unknown('unknown');

  const Availability(this.code);
  final String code;

  static Availability of(String? code) => Availability.values.firstWhere(
    (a) => a.code == code,
    orElse: () => Availability.unknown,
  );
}

/// What the link of an offer opens.
enum UrlKind {
  product('product'),
  search('search'),
  none('none');

  const UrlKind(this.code);
  final String code;

  static UrlKind of(String? code) => UrlKind.values.firstWhere(
    (a) => a.code == code,
    orElse: () => UrlKind.none,
  );
}

/// How old a checked price is.
enum PriceAge { fresh, stale }

/// An offer of one shop for one product, as a person (or a permitted feed)
/// checked it. See DB v17 `store_offers`.
class StoreOffer {
  const StoreOffer({
    required this.id,
    required this.productId,
    required this.storeId,
    required this.storeName,
    required this.chain,
    required this.city,
    required this.price,
    required this.oldPrice,
    required this.availability,
    required this.url,
    required this.urlKind,
    required this.source,
    required this.method,
    required this.verification,
    required this.checkedAt,
    this.volumeText,
    this.variantText,
    this.note,
  });

  final int id;
  final int productId;
  final int storeId;
  final String storeName;
  final String chain;
  final String city;

  /// Tenge; null: the price was not confirmed.
  final int? price;
  final int? oldPrice;
  final Availability availability;
  final String? url;
  final UrlKind urlKind;
  final String source;
  final String method;
  final String verification;

  /// When the offer was last checked (epoch ms).
  final int checkedAt;
  final String? volumeText;
  final String? variantText;
  final String? note;

  bool get isVerified => verification == 'verified';
  bool get hasPrice => price != null;
  bool get hasLink => url != null && urlKind != UrlKind.none;

  /// A price is called current only for a short time after the check; after
  /// that the screen says "price at the last check" with the date.
  static const freshFor = Duration(days: 2);

  PriceAge ageAt(DateTime now) =>
      now.difference(DateTime.fromMillisecondsSinceEpoch(checkedAt)) <= freshFor
      ? PriceAge.fresh
      : PriceAge.stale;

  factory StoreOffer.fromMap(Map<String, Object?> m) => StoreOffer(
    id: m['id']! as int,
    productId: m['product_id']! as int,
    storeId: m['store_id']! as int,
    storeName: (m['store_name'] as String?) ?? '',
    chain: (m['chain'] as String?) ?? '',
    city: (m['city'] as String?) ?? '',
    price: m['price'] as int?,
    oldPrice: m['old_price'] as int?,
    availability: Availability.of(m['availability'] as String?),
    url: m['url'] as String?,
    urlKind: UrlKind.of(m['url_kind'] as String?),
    source: m['source']! as String,
    method: m['method']! as String,
    verification: m['verification']! as String,
    checkedAt: m['checked_at']! as int,
    volumeText: m['volume_text'] as String?,
    variantText: m['variant_text'] as String?,
    note: m['note'] as String?,
  );
}
