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
  final bool isFavorite;
  final bool featured;
  final bool trending;

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
    isFavorite: (m['is_fav'] as int? ?? 0) == 1,
    featured: (m['featured'] as int? ?? 0) == 1,
    trending: (m['trending'] as int? ?? 0) == 1,
  );
}

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
  });

  final int storeId;
  final String storeName;
  final int distanceM;
  final String address;
  final double rating;
  final int price;
  final bool inStock;

  String get distanceLabel => distanceM >= 1000
      ? trf('{v0} км от вас', {
          'v0': (distanceM / 1000).toStringAsFixed(1).replaceAll('.', ','),
        })
      : trf('{distanceM} м от вас', {'distanceM': distanceM});

  factory StorePrice.fromMap(Map<String, Object?> m) => StorePrice(
    storeId: m['store_id'] as int,
    storeName: m['name'] as String,
    distanceM: m['distance_m'] as int,
    address: m['address'] as String,
    rating: (m['rating'] as num).toDouble(),
    price: m['price'] as int,
    inStock: (m['in_stock'] as int? ?? 1) == 1,
  );
}
