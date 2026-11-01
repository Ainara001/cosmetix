import 'package:cosmetix/core/constants/app_constants.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/services/ingredient_catalog.dart';

enum ProductStatus {
  any('Любой статус'),
  inStock('В наличии'),
  outOfStock('Нет в наличии'),
  sale('Со скидкой');

  const ProductStatus(this.label);
  final String label;
}

enum ProductSort {
  forYou('Для вас'),
  newest('По новизне'),
  priceAsc('Сначала дешёвые'),
  priceDesc('Сначала дорогие'),
  name('По названию');

  const ProductSort(this.label);
  final String label;

  /// Catalog options: "For you" exists only after the Beauty Test.
  static List<ProductSort> catalogOptions({required bool hasProfile}) => [
    if (hasProfile) forYou,
    newest,
    priceAsc,
    priceDesc,
  ];

  static const cartOptions = [newest, priceAsc, priceDesc, name];
}

/// Search + filter parameters shared by Catalog, Cart and Filters screens.
class ProductFilter {
  const ProductFilter({
    this.name = '',
    this.category,
    this.zone,
    this.status = ProductStatus.any,
    this.minPrice = 0,
    this.maxPrice = AppConstants.maxPrice,
    this.withIngredients = const {},
    this.withoutIngredients = const {},
    this.anyIngredient = false,
  });

  final String name;
  final String? category;
  final String? zone;
  final ProductStatus status;
  final int minPrice;
  final int maxPrice;

  /// [IngredientGroup] codes the composition must contain / must not contain.
  final Set<String> withIngredients;
  final Set<String> withoutIngredients;

  /// With several wanted ingredients: any of them (true) or all (false).
  final bool anyIngredient;

  bool get hasIngredientFilter =>
      withIngredients.isNotEmpty || withoutIngredients.isNotEmpty;

  bool get isDefault =>
      name.isEmpty &&
      category == null &&
      zone == null &&
      status == ProductStatus.any &&
      minPrice == 0 &&
      maxPrice == AppConstants.maxPrice &&
      !hasIngredientFilter;

  ProductFilter copyWith({
    String? name,
    Object? category = _keep,
    Object? zone = _keep,
    ProductStatus? status,
    int? minPrice,
    int? maxPrice,
    Set<String>? withIngredients,
    Set<String>? withoutIngredients,
    bool? anyIngredient,
  }) {
    return ProductFilter(
      name: name ?? this.name,
      category: identical(category, _keep)
          ? this.category
          : category as String?,
      zone: identical(zone, _keep) ? this.zone : zone as String?,
      status: status ?? this.status,
      minPrice: minPrice ?? this.minPrice,
      maxPrice: maxPrice ?? this.maxPrice,
      withIngredients: withIngredients ?? this.withIngredients,
      withoutIngredients: withoutIngredients ?? this.withoutIngredients,
      anyIngredient: anyIngredient ?? this.anyIngredient,
    );
  }

  static const _keep = Object();

  bool matches(Product p, {int? priceOverride}) {
    final q = name.trim().toLowerCase();
    if (q.isNotEmpty && !_matchesText(p, q)) return false;
    if (!_matchesIngredients(p)) return false;
    if (category != null && p.category != category) return false;
    if (zone != null && p.zone != zone) return false;
    switch (status) {
      case ProductStatus.any:
        break;
      case ProductStatus.inStock:
        if (!p.inStock) return false;
      case ProductStatus.outOfStock:
        if (p.inStock) return false;
      case ProductStatus.sale:
        if (!p.hasDiscount) return false;
    }
    final price = priceOverride ?? p.price;
    return price >= minPrice && price <= maxPrice;
  }

  /// The search text hits the name, or the composition: an ingredient word
  /// ("ниацинамид", "bha") or a longer piece of the INCI list.
  static bool _matchesText(Product p, String q) {
    if ('${p.brand} ${p.name} ${p.category}'.toLowerCase().contains(q)) {
      return true;
    }
    if (q.length >= 4 && p.inci.toLowerCase().contains(q)) return true;
    final found = IngredientCatalog.of(p);
    return IngredientCatalog.forQuery(q).any((g) => found.contains(g.code));
  }

  bool _matchesIngredients(Product p) {
    if (!hasIngredientFilter) return true;
    final found = IngredientCatalog.of(p);
    if (withIngredients.isNotEmpty) {
      final ok = anyIngredient
          ? withIngredients.any(found.contains)
          : withIngredients.every(found.contains);
      if (!ok) return false;
    }
    for (final code in withoutIngredients) {
      // a product without a published composition cannot be confirmed "free of"
      if (p.inci.trim().isEmpty || found.contains(code)) return false;
    }
    return true;
  }

  static List<Product> apply(
    Iterable<Product> source,
    ProductFilter filter,
    ProductSort sort,
  ) {
    final list = source.where(filter.matches).toList();
    switch (sort) {
      case ProductSort.forYou: // ranked by the personal recommendation service
      case ProductSort.newest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case ProductSort.priceAsc:
        list.sort((a, b) => a.price.compareTo(b.price));
      case ProductSort.priceDesc:
        list.sort((a, b) => b.price.compareTo(a.price));
      case ProductSort.name:
        list.sort((a, b) => a.name.compareTo(b.name));
    }
    return list;
  }
}
