import 'package:cosmetix/services/server/server_exceptions.dart';

/// A product as the server's catalog API returns it. These are plain data
/// objects: they are not the app's own `Product` and nothing converts them yet
/// (the app still reads its local SQLite catalog).
class ServerProduct {
  const ServerProduct({
    required this.id,
    required this.brand,
    required this.category,
    required this.name,
    required this.zone,
    required this.price,
    required this.priceSource,
    required this.oldPrice,
    required this.inStock,
    required this.art,
    required this.color,
    required this.shade,
    required this.description,
    required this.naturalPercent,
    required this.featured,
    required this.trending,
    required this.inci,
    required this.sourceUrl,
    required this.country,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String brand;
  final String category;
  final String name;
  final String zone;

  /// Tenge, whole numbers.
  final int price;

  /// `demo` = a placeholder value from the app's seed, NOT a real shop price;
  /// `admin` = entered in the admin panel. Show a demo price as such.
  final String priceSource;
  final int? oldPrice;
  final bool inStock;
  final String art;
  final int color;
  final int? shade;
  final String description;
  final int naturalPercent;
  final bool featured;
  final bool trending;

  /// The full ingredient list as published, and the page it was taken from.
  final String inci;
  final String sourceUrl;

  /// Country of the manufacturer; null while nobody has filled it in.
  final String? country;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isDemoPrice => priceSource == 'demo';

  factory ServerProduct.fromJson(Object? raw) {
    final m = _map(raw, 'product');
    return ServerProduct(
      id: _int(m, 'id'),
      brand: _str(m, 'brand'),
      category: _str(m, 'category'),
      name: _str(m, 'name'),
      zone: _str(m, 'zone'),
      price: _int(m, 'price'),
      priceSource: _str(m, 'priceSource'),
      oldPrice: _intOrNull(m, 'oldPrice'),
      inStock: _bool(m, 'inStock'),
      art: _str(m, 'art'),
      color: _int(m, 'color'),
      shade: _intOrNull(m, 'shade'),
      description: _str(m, 'description'),
      naturalPercent: _int(m, 'naturalPercent'),
      featured: _bool(m, 'featured'),
      trending: _bool(m, 'trending'),
      inci: _str(m, 'inci'),
      sourceUrl: _str(m, 'sourceUrl'),
      country: _strOrNull(m, 'country'),
      createdAt: _date(m, 'createdAt'),
      updatedAt: _date(m, 'updatedAt'),
    );
  }
}

class ServerCatalogPage {
  const ServerCatalogPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  final List<ServerProduct> items;
  final int total;
  final int limit;
  final int offset;

  factory ServerCatalogPage.fromJson(Object? raw) {
    final m = _map(raw, 'catalog page');
    final items = m['items'];
    if (items is! List) throw const ServerBadResponse('"items" is missing');
    return ServerCatalogPage(
      items: [for (final i in items) ServerProduct.fromJson(i)],
      total: _int(m, 'total'),
      limit: _int(m, 'limit'),
      offset: _int(m, 'offset'),
    );
  }
}

/// One shop's offer. `source == 'demo'` means a placeholder, not a real price.
class ServerOffer {
  const ServerOffer({
    required this.storeId,
    required this.price,
    required this.inStock,
    required this.qty,
    required this.source,
  });

  final int storeId;
  final int price;
  final bool inStock;
  final int? qty;
  final String source;

  bool get isDemo => source == 'demo';

  factory ServerOffer._fromJson(Object? raw) {
    final m = _map(raw, 'offer');
    return ServerOffer(
      storeId: _int(m, 'storeId'),
      price: _int(m, 'price'),
      inStock: _bool(m, 'inStock'),
      qty: _intOrNull(m, 'qty'),
      source: _str(m, 'source'),
    );
  }
}

/// A product with what the list does not carry: the ingredients the app
/// explains, what it suits, and the offers of the shops.
class ServerProductDetails {
  const ServerProductDetails({
    required this.product,
    required this.ingredientIds,
    required this.traits,
    required this.offers,
  });

  final ServerProduct product;
  final List<int> ingredientIds;

  /// `skinTypes`, `colorTypes`, `undertones`, `concerns`, `tags`.
  final Map<String, List<String>> traits;
  final List<ServerOffer> offers;

  factory ServerProductDetails.fromJson(Object? raw) {
    final m = _map(raw, 'product details');
    final ing = m['ingredients'];
    final traits = m['traits'];
    final prices = m['prices'];
    if (ing is! List || traits is! Map || prices is! List) {
      throw const ServerBadResponse('The product details are incomplete');
    }
    return ServerProductDetails(
      product: ServerProduct.fromJson(m),
      ingredientIds: [for (final i in ing) _int(_map(i, 'ingredient'), 'id')],
      traits: {
        for (final e in traits.entries)
          '${e.key}': [
            for (final v in (e.value is List ? e.value as List : const []))
              if (v is String) v,
          ],
      },
      offers: [for (final p in prices) ServerOffer._fromJson(p)],
    );
  }
}

// --- strict readers: a wrong shape is a ServerBadResponse, never a crash ---

Map<Object?, Object?> _map(Object? v, String what) {
  if (v is Map) return v.cast<Object?, Object?>();
  throw ServerBadResponse('Expected an object for $what');
}

int _int(Map<Object?, Object?> m, String k) {
  final v = m[k];
  if (v is int) return v;
  throw ServerBadResponse('"$k" must be an integer');
}

int? _intOrNull(Map<Object?, Object?> m, String k) {
  final v = m[k];
  if (v == null) return null;
  if (v is int) return v;
  throw ServerBadResponse('"$k" must be an integer or null');
}

String _str(Map<Object?, Object?> m, String k) {
  final v = m[k];
  if (v is String) return v;
  throw ServerBadResponse('"$k" must be a string');
}

String? _strOrNull(Map<Object?, Object?> m, String k) {
  final v = m[k];
  if (v == null) return null;
  if (v is String) return v;
  throw ServerBadResponse('"$k" must be a string or null');
}

bool _bool(Map<Object?, Object?> m, String k) {
  final v = m[k];
  if (v is bool) return v;
  throw ServerBadResponse('"$k" must be true or false');
}

DateTime _date(Map<Object?, Object?> m, String k) {
  final v = m[k];
  final d = v is String ? DateTime.tryParse(v) : null;
  if (d != null) return d;
  throw ServerBadResponse('"$k" must be a date');
}
