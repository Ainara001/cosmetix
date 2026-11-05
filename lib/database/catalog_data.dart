import 'dart:convert';

import 'package:flutter/services.dart';

import 'package:cosmetix/database/try_on_data.dart';

/// Curated "who is this product for" lists of a catalog product (the AI
/// classifier can add more, see `product_ai_classification`).
class ProductTraits {
  const ProductTraits({
    this.skinTypes = const [],
    this.colorTypes = const [],
    this.undertones = const [],
    this.concerns = const [],
    this.tags = const [],
  });

  final List<String> skinTypes;
  final List<String> colorTypes;
  final List<String> undertones;
  final List<String> concerns;
  final List<String> tags;

  factory ProductTraits.fromJson(Map<String, Object?> j) => ProductTraits(
    skinTypes: _strings(j['skin_types']),
    colorTypes: _strings(j['color_types']),
    undertones: _strings(j['undertones']),
    concerns: _strings(j['concerns']),
    tags: _strings(j['tags']),
  );
}

/// One product of `assets/catalog/products.json`.
class ProductSeed {
  const ProductSeed({
    required this.brand,
    required this.name,
    required this.category,
    required this.zone,
    required this.price,
    required this.oldPrice,
    required this.inStock,
    required this.art,
    required this.photo,
    required this.color,
    required this.description,
    required this.naturalPercent,
    required this.inci,
    required this.sourceUrl,
    required this.featured,
    required this.trending,
    required this.shade,
    required this.ingredients,
    required this.traits,
    required this.legacyName,
    required this.addedInDbVersion,
    required this.country,
    required this.countrySource,
    required this.demo,
    this.tryOn,
  });

  final String brand;
  final String name;
  final String category;
  final String zone;
  final int price;
  final int? oldPrice;
  final bool inStock;

  /// Drawing kind (`bottle`, `tube`, ...).
  final String art;

  /// Photo from `assets/products/` (see CREDITS.txt there).
  final String? photo;
  final int color;
  final String description;
  final int naturalPercent;

  /// Full ingredient list (INCI) as published, and the page it was taken from.
  final String inci;
  final String sourceUrl;
  final bool featured;
  final bool trending;

  /// Representative colour (ARGB) of a makeup product.
  final int? shade;

  /// 1-based ids of `ingredients.json`.
  final List<int> ingredients;
  final ProductTraits? traits;

  /// `brand|name` the product had in the first demo catalog (DB v7 turned
  /// those rows into real products); null when the product did not change.
  final String? legacyName;

  /// Database version whose migration first brought the product.
  final int addedInDbVersion;

  /// Country of manufacture, only when [countrySource] proves it; null
  /// otherwise (never guessed).
  final String? country;
  final String? countrySource;

  /// The product itself is made up (the Cosmetix gift set).
  final bool demo;

  /// How the product looks on a face for the virtual try-on (null: the catalog
  /// says nothing, the product is not offered for try-on).
  final TryOnSeed? tryOn;

  /// `brand|name`, the key of a product across databases.
  String get key => '$brand|$name';

  /// What the `art` column stores: the drawing kind, plus `|photo` when the
  /// product has a photo (see `ProductArt`).
  String get artValue => photo == null ? art : '$art|$photo';

  factory ProductSeed.fromJson(Map<String, Object?> j) {
    String str(String k) {
      final v = j[k];
      if (v is! String) throw FormatException('products.json: "$k" missing', j);
      return v;
    }

    int integer(String k) {
      final v = j[k];
      if (v is! int) throw FormatException('products.json: "$k" missing', j);
      return v;
    }

    final country = _blankToNull(j['country']);
    final countrySource = _blankToNull(j['country_source']);
    final name = '${j['brand']}|${j['name']}';
    // a country without a checkable source would be a guess
    if (country != null &&
        (countrySource == null ||
            !(Uri.tryParse(countrySource)?.hasScheme ?? false))) {
      throw FormatException('products.json: country of $name has no source');
    }
    if (country == null && countrySource != null) {
      throw FormatException('products.json: source of $name has no country');
    }
    final demo = j['demo'] == true;
    final sourceUrl = (j['source_url'] as String?) ?? '';
    if (!demo && sourceUrl.isEmpty) {
      throw FormatException('products.json: product $name has no source_url');
    }
    final traits = j['traits'];
    return ProductSeed(
      brand: str('brand'),
      name: str('name'),
      category: str('category'),
      zone: (j['zone'] as String?) ?? '',
      price: integer('price'),
      oldPrice: j['old_price'] as int?,
      inStock: j['in_stock'] != false,
      art: str('art'),
      photo: j['photo'] as String?,
      color: integer('color'),
      description: (j['description'] as String?) ?? '',
      naturalPercent: integer('natural_percent'),
      inci: (j['inci'] as String?) ?? '',
      sourceUrl: sourceUrl,
      featured: j['featured'] == true,
      trending: j['trending'] == true,
      shade: j['shade'] as int?,
      ingredients: [
        for (final e in (j['ingredients'] as List? ?? const [])) e as int,
      ],
      traits: traits is Map<String, Object?>
          ? ProductTraits.fromJson(traits)
          : null,
      legacyName: j['legacy_name'] as String?,
      addedInDbVersion: (j['added_in_db_version'] as int?) ?? 7,
      country: country,
      countrySource: countrySource,
      demo: demo,
      tryOn: j['try_on'] is Map<String, Object?>
          ? TryOnSeed.fromJson(name, j['try_on'] as Map<String, Object?>)
          : null,
    );
  }
}

/// One row of `assets/catalog/ingredients.json`.
class IngredientSeed {
  const IngredientSeed({
    required this.id,
    required this.name,
    required this.description,
    required this.risk,
    required this.isAllergen,
    required this.groupKey,
  });

  final int id;
  final String name;
  final String description;
  final int risk;
  final bool isAllergen;
  final String? groupKey;

  factory IngredientSeed.fromJson(Map<String, Object?> j) => IngredientSeed(
    id: j['id'] as int,
    name: j['name'] as String,
    description: (j['description'] as String?) ?? '',
    risk: (j['risk'] as int?) ?? 0,
    isAllergen: j['is_allergen'] == true,
    groupKey: j['group_key'] as String?,
  );
}

/// The product catalog that ships with the app, read from JSON assets
/// (`assets/catalog/`). The position of a product in the list is its id in a
/// fresh database (id = position + 1), so new products are only appended.
class CatalogData {
  CatalogData({required this.ingredients, required this.products}) {
    final seen = <String>{};
    for (final p in products) {
      if (!seen.add(p.key)) {
        throw FormatException('products.json: ${p.key} is listed twice');
      }
      for (final i in p.ingredients) {
        if (i < 1 || i > ingredients.length) {
          throw FormatException('products.json: ${p.key} uses ingredient $i');
        }
      }
    }
  }

  static const ingredientsAsset = 'assets/catalog/ingredients.json';
  static const productsAsset = 'assets/catalog/products.json';

  final List<IngredientSeed> ingredients;
  final List<ProductSeed> products;

  /// Index in [products] of the first product added after DB v9.
  int get firstNewProduct {
    final i = products.indexWhere((p) => p.addedInDbVersion >= 10);
    return i < 0 ? products.length : i;
  }

  Map<String, ProductSeed> get byKey => {for (final p in products) p.key: p};

  factory CatalogData.parse(String ingredientsJson, String productsJson) {
    List<Map<String, Object?>> list(String raw, String key) {
      final j = jsonDecode(raw);
      if (j is! Map || j[key] is! List) {
        throw FormatException('$key: the JSON has no "$key" list');
      }
      return [for (final e in j[key] as List) (e as Map).cast()];
    }

    return CatalogData(
      ingredients: [
        for (final e in list(ingredientsJson, 'ingredients'))
          IngredientSeed.fromJson(e),
      ],
      products: [
        for (final e in list(productsJson, 'products')) ProductSeed.fromJson(e),
      ],
    );
  }

  static CatalogData? _cache;

  /// How an asset file is read. The app reads the bundled files; plain Dart
  /// tests (no Flutter binding, real HTTP) read them from the project folder,
  /// see `test/flutter_test_config.dart`.
  static Future<String> Function(String path) assetReader =
      rootBundle.loadString;

  /// Reads the catalog once per run (the files are bundled, they never
  /// change). Pass [reader] in tests to read something else; that is not
  /// cached.
  static Future<CatalogData> load([
    Future<String> Function(String path)? reader,
  ]) async {
    if (reader == null && _cache != null) return _cache!;
    final read = reader ?? assetReader;
    final data = CatalogData.parse(
      await read(ingredientsAsset),
      await read(productsAsset),
    );
    if (reader == null) _cache = data;
    return data;
  }
}

List<String> _strings(Object? v) => [
  if (v is List)
    for (final e in v) e as String,
];

String? _blankToNull(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}
