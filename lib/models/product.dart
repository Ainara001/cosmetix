import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/models/store_offer.dart';

class Product {
  const Product({
    required this.id,
    required this.brand,
    required this.name,
    required this.category,
    required this.zone,
    required this.price,
    this.oldPrice,
    required this.art,
    required this.color,
    required this.description,
    required this.naturalPercent,
    required this.createdAt,
    this.inci = '',
    this.sourceUrl = '',
    this.country,
    this.countrySource,
    this.shade,
    this.isFavorite = false,
    this.featured = false,
    this.trending = false,
    bool inStock = true,
    Availability? availability,
    this.priceCheckedAt,
  }) : availability =
           availability ??
           (inStock ? Availability.unknown : Availability.outOfStock);

  final int id;
  final String brand;
  final String name;
  final String category;
  final String zone;

  /// The lowest VERIFIED shop price in tenge; 0 when no verified price exists
  /// (the screens then say "price not confirmed"). It is never the demo value
  /// of the seed.
  final int price;
  final int? oldPrice;

  /// False only when a verified offer says the product is out of stock;
  /// "unknown" is not "out of stock" (so recommendations keep such products).
  bool get inStock => availability != Availability.outOfStock;

  /// What the verified offers say about stock: in stock, out of stock, or
  /// unknown (nothing checked).
  final Availability availability;

  /// When the shown price was checked (epoch ms); null without a price.
  final int? priceCheckedAt;

  bool get hasPrice => price > 0;
  final String art;
  final int color;
  final String description;
  final int naturalPercent;
  final int createdAt;

  /// Full ingredient list (INCI) as published, and the page it comes from.
  final String inci;
  final String sourceUrl;

  /// Country of manufacture and the page that states it. Both are null when
  /// no checkable source was found: the value is never guessed.
  final String? country;
  final String? countrySource;

  /// Representative colour (ARGB) of a makeup product, if known.
  final int? shade;
  final bool isFavorite;
  final bool featured;
  final bool trending;

  /// Foundation / cushion: matched with the skin tone, not with the palette.
  bool get isBaseMakeup =>
      category == 'Макияж' &&
      RegExp(
        r'cushion|foundation|кушон|тональн',
        caseSensitive: false,
      ).hasMatch('$name $description');

  bool get hasDiscount => oldPrice != null && oldPrice! > price;

  int get discountPercent =>
      hasDiscount ? (((oldPrice! - price) / oldPrice!) * 100).round() : 0;

  Product copyWith({bool? isFavorite}) => Product(
    id: id,
    brand: brand,
    name: name,
    category: category,
    zone: zone,
    price: price,
    oldPrice: oldPrice,
    art: art,
    color: color,
    description: description,
    naturalPercent: naturalPercent,
    createdAt: createdAt,
    inci: inci,
    sourceUrl: sourceUrl,
    country: country,
    countrySource: countrySource,
    shade: shade,
    isFavorite: isFavorite ?? this.isFavorite,
    featured: featured,
    trending: trending,
    availability: availability,
    priceCheckedAt: priceCheckedAt,
  );

  factory Product.fromMap(Map<String, Object?> m) => Product(
    id: m['id'] as int,
    brand: m['brand'] as String,
    name: m['name'] as String,
    category: m['category'] as String? ?? '',
    zone: m['zone'] as String? ?? '',
    // only a verified shop price is a price; the seed's demo value is ignored
    price: m['verified_price'] as int? ?? 0,
    oldPrice: m['verified_old_price'] as int?,
    availability:
        (m['offers_out_of_stock'] as int? ?? 0) > 0 &&
            (m['offers_in_stock'] as int? ?? 0) == 0
        ? Availability.outOfStock
        : (m['offers_in_stock'] as int? ?? 0) > 0
        ? Availability.inStock
        : Availability.unknown,
    priceCheckedAt: m['verified_checked_at'] as int?,
    art: m['art'] as String? ?? 'bottle',
    color: m['color'] as int? ?? 0xFFF4B6C2,
    description: m['description'] as String? ?? '',
    naturalPercent: m['natural_percent'] as int? ?? 80,
    createdAt: m['created_at'] as int? ?? 0,
    inci: m['inci'] as String? ?? '',
    sourceUrl: m['source_url'] as String? ?? '',
    country: _nonEmpty(m['country']),
    countrySource: _nonEmpty(m['country_source']),
    shade: m['shade'] as int?,
    isFavorite: (m['is_fav'] as int? ?? 0) == 1,
    featured: (m['featured'] as int? ?? 0) == 1,
    trending: (m['trending'] as int? ?? 0) == 1,
  );
}

String? _nonEmpty(Object? v) => v is String && v.trim().isNotEmpty ? v : null;

/// Stock of a product in a shop.
enum StockLevel { inStock, low, out, unknown }

/// Price of one product in one store.
class StorePrice {
  const StorePrice({
    required this.storeId,
    required this.storeName,
    required this.distanceM,
    required this.address,
    required this.rating,
    required this.price,
    required this.inStock,
    this.lat,
    this.lng,
    this.chain = '',
    this.hours = '',
    this.qty,
    this.demo = false,
    this.updatedAt,
    this.locationSource = '',
    this.availability = Availability.unknown,
    this.url,
    this.urlKind = UrlKind.none,
    this.sourceText = '',
  });

  final int storeId;
  final String storeName;

  /// Metres from the user (or from the city centre until the location is
  /// known).
  final int distanceM;
  final String address;
  final double rating;
  final int price;
  final bool inStock;
  final double? lat;
  final double? lng;
  final String chain;
  final String hours;

  /// Units in stock, null when unknown.
  final int? qty;

  /// True for the demo offers (no real stock feed behind them).
  final bool demo;

  /// When a real feed last updated this offer (null for demo data).
  final int? updatedAt;

  /// Where the shop's position comes from.
  final String locationSource;

  /// Stock as checked: `unknown` is not `out of stock`.
  final Availability availability;

  /// Link to the product (or only to a search) on the shop's site, if any.
  final String? url;
  final UrlKind urlKind;

  /// Where the price comes from (shown with the check date).
  final String sourceText;

  bool get hasPosition => lat != null && lng != null;

  /// A few units left (3 or fewer).
  StockLevel get level => availability == Availability.unknown
      ? StockLevel.unknown
      : !inStock
      ? StockLevel.out
      : (qty != null && qty! <= 3 ? StockLevel.low : StockLevel.inStock);

  /// Same offer with a distance counted from the user's position.
  StorePrice withDistance(int meters) => StorePrice(
    storeId: storeId,
    storeName: storeName,
    distanceM: meters,
    address: address,
    rating: rating,
    price: price,
    inStock: inStock,
    lat: lat,
    lng: lng,
    chain: chain,
    hours: hours,
    qty: qty,
    demo: demo,
    updatedAt: updatedAt,
    locationSource: locationSource,
    availability: availability,
    url: url,
    urlKind: urlKind,
    sourceText: sourceText,
  );

  String get distanceLabel => distanceM >= 1000
      ? trf('{v0} км от вас', {
          'v0': (distanceM / 1000).toStringAsFixed(1).replaceAll('.', ','),
        })
      : trf('{distanceM} м от вас', {'distanceM': distanceM});

  /// "открыто до 22:00" / "закрыто, откроется в 10:00"; empty when unknown.
  String openStatus(DateTime now) => openStatusOf(hours, now);

  factory StorePrice.fromMap(Map<String, Object?> m) => StorePrice(
    storeId: m['store_id'] as int,
    storeName: m['name'] as String,
    distanceM: m['distance_m'] as int,
    address: m['address'] as String,
    rating: (m['rating'] as num).toDouble(),
    price: m['price'] as int,
    inStock:
        Availability.of(m['availability'] as String?) !=
        Availability.outOfStock,
    lat: (m['lat'] as num?)?.toDouble(),
    lng: (m['lng'] as num?)?.toDouble(),
    chain: m['chain'] as String? ?? '',
    hours: m['hours'] as String? ?? '',
    qty: m['qty'] as int?,
    demo: false,
    updatedAt: m['updated_at'] as int?,
    locationSource: m['loc_source'] as String? ?? '',
    availability: Availability.of(m['availability'] as String?),
    url: m['url'] as String?,
    urlKind: UrlKind.of(m['url_kind'] as String?),
    sourceText: m['offer_source'] as String? ?? '',
  );
}

/// A shop on the map (independent of any product).
class StoreInfo {
  const StoreInfo({
    required this.id,
    required this.name,
    required this.chain,
    required this.address,
    required this.hours,
    required this.lat,
    required this.lng,
    required this.source,
    this.distanceM = 0,
  });

  final int id;
  final String name;
  final String chain;
  final String address;
  final String hours;
  final double lat;
  final double lng;
  final String source;
  final int distanceM;

  StoreInfo withDistance(int meters) => StoreInfo(
    id: id,
    name: name,
    chain: chain,
    address: address,
    hours: hours,
    lat: lat,
    lng: lng,
    source: source,
    distanceM: meters,
  );

  factory StoreInfo.fromMap(Map<String, Object?> m) => StoreInfo(
    id: m['id'] as int,
    name: m['name'] as String,
    chain: m['chain'] as String? ?? '',
    address: m['address'] as String,
    hours: m['hours'] as String? ?? '',
    lat: (m['lat'] as num).toDouble(),
    lng: (m['lng'] as num).toDouble(),
    source: m['source'] as String? ?? '',
    distanceM: m['distance_m'] as int? ?? 0,
  );
}

/// "открыто до 22:00" / "закрыто, откроется в 10:00" from opening hours like
/// "Ежедневно 10:00–22:00"; empty when the hours are unknown.
String openStatusOf(String hours, DateTime now) {
  final m = RegExp(
    r'(\d{1,2}):(\d{2})\s*[–-]\s*(\d{1,2}):(\d{2})',
  ).firstMatch(hours);
  if (m == null) return '';
  final open = int.parse(m[1]!) * 60 + int.parse(m[2]!);
  final close = int.parse(m[3]!) * 60 + int.parse(m[4]!);
  final t = now.hour * 60 + now.minute;
  String hm(int v) =>
      '${(v ~/ 60).toString().padLeft(2, '0')}:${(v % 60).toString().padLeft(2, '0')}';
  if (t >= open && t < close) {
    return trf('открыто до {v0}', {'v0': hm(close)});
  }
  return trf('закрыто, откроется в {v0}', {'v0': hm(open)});
}
