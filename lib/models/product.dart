import 'package:cosmetix/core/i18n/tr.dart';

class Product {
  const Product({
    required this.id,
    required this.brand,
    required this.name,
    required this.category,
    required this.zone,
    required this.price,
    this.oldPrice,
    required this.inStock,
    required this.art,
    required this.color,
    required this.description,
    required this.naturalPercent,
    required this.createdAt,
    this.inci = '',
    this.sourceUrl = '',
    this.shade,
    this.isFavorite = false,
    this.featured = false,
    this.trending = false,
  });

  final int id;
  final String brand;
  final String name;
  final String category;
  final String zone;
  final int price;
  final int? oldPrice;
  final bool inStock;
  final String art;
  final int color;
  final String description;
  final int naturalPercent;
  final int createdAt;

  /// Full ingredient list (INCI) as published, and the page it comes from.
  final String inci;
  final String sourceUrl;

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
    inStock: inStock,
    art: art,
    color: color,
    description: description,
    naturalPercent: naturalPercent,
    createdAt: createdAt,
    inci: inci,
    sourceUrl: sourceUrl,
    shade: shade,
    isFavorite: isFavorite ?? this.isFavorite,
    featured: featured,
    trending: trending,
  );

  factory Product.fromMap(Map<String, Object?> m) => Product(
    id: m['id'] as int,
    brand: m['brand'] as String,
    name: m['name'] as String,
    category: m['category'] as String? ?? '',
    zone: m['zone'] as String? ?? '',
    price: m['price'] as int,
    oldPrice: m['old_price'] as int?,
    inStock: (m['in_stock'] as int? ?? 1) == 1,
    art: m['art'] as String? ?? 'bottle',
    color: m['color'] as int? ?? 0xFFF4B6C2,
    description: m['description'] as String? ?? '',
    naturalPercent: m['natural_percent'] as int? ?? 80,
    createdAt: m['created_at'] as int? ?? 0,
    inci: m['inci'] as String? ?? '',
    sourceUrl: m['source_url'] as String? ?? '',
    shade: m['shade'] as int?,
    isFavorite: (m['is_fav'] as int? ?? 0) == 1,
    featured: (m['featured'] as int? ?? 0) == 1,
    trending: (m['trending'] as int? ?? 0) == 1,
  );
}

/// Stock of a product in a shop.
enum StockLevel { inStock, low, out }

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
    this.demo = true,
    this.updatedAt,
    this.locationSource = '',
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

  bool get hasPosition => lat != null && lng != null;

  /// A few units left (3 or fewer).
  StockLevel get level => !inStock
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
    inStock: (m['in_stock'] as int? ?? 1) == 1,
    lat: (m['lat'] as num?)?.toDouble(),
    lng: (m['lng'] as num?)?.toDouble(),
    chain: m['chain'] as String? ?? '',
    hours: m['hours'] as String? ?? '',
    qty: m['qty'] as int?,
    demo: (m['offer_source'] as String? ?? 'demo') == 'demo',
    updatedAt: m['updated_at'] as int?,
    locationSource: m['loc_source'] as String? ?? '',
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
