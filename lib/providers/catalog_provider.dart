import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/foundation.dart';

import 'package:cosmetix/core/beauty/beauty_codes.dart';

import 'package:cosmetix/models/palette_models.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/models/recommendation.dart';
import 'package:cosmetix/repositories/product_repository.dart';
import 'package:cosmetix/services/ai/ai_client.dart';
import 'package:cosmetix/services/ai/recommendation_refiner.dart';
import 'package:cosmetix/services/age_safety.dart';
import 'package:cosmetix/services/ingredient_catalog.dart';
import 'package:cosmetix/services/recommendation_service.dart';

/// Products, favourites, search history and the personalized ranking.
class CatalogProvider extends ChangeNotifier {
  CatalogProvider(this._repo, this._reco);

  final ProductRepository _repo;
  final RecommendationService _reco;

  PersonalizationContext _ctx = const PersonalizationContext.empty();
  Map<int, Recommendation> _byProduct = {};
  String _signature = '';
  String Function()? _signatureOf;

  List<Product> products = [];

  /// Line / variant / palette facts of the products that have them (DB v16),
  /// by product id. Empty when they could not be read: the lists then simply
  /// show the products without them.
  Map<int, VariantSummary> structure = {};
  List<String> history = [];
  bool loading = false;
  String? error;
  int? _userId;

  Future<void> load(int userId) async {
    _userId = userId;
    loading = true;
    error = null;
    notifyListeners();
    try {
      products = await _repo.getAll(userId);
      try {
        structure = await _repo.structure();
      } catch (e) {
        structure = {};
        debugPrint('catalog structure failed: $e');
      }
      history = await _repo.getHistory(userId);
      await _loadPersonalization(userId);
    } catch (e) {
      error = tr('Не удалось загрузить каталог');
      debugPrint('catalog load failed: $e');
    }
    loading = false;
    _signature = _signatureOf?.call() ?? '';
    notifyListeners();
  }

  void reset() {
    products = [];
    structure = {};
    history = [];
    _userId = null;
    _ctx = const PersonalizationContext.empty();
    _byProduct = {};
    _signature = '';
    notifyListeners();
  }

  // ---- personalization ----

  /// True once the Beauty Test is completed: the catalog defaults to "For you".
  bool get hasProfile => _ctx.profile.isComplete;

  /// Sensitive skin: the type or a concern about redness (a patch test is
  /// worth the time).
  bool get sensitiveSkin =>
      _ctx.profile.skinType == SkinType.sensitive ||
      _ctx.profile.concerns.contains(SkinConcern.sensitivity);

  PersonalizationContext get personalization => _ctx;

  Future<void> _loadPersonalization(int userId) async {
    try {
      _ctx = await _reco.loadContext(userId);
    } catch (e) {
      debugPrint('personalization failed: $e');
      _ctx = const PersonalizationContext.empty();
    }
    _aiOrder = {};
    _recompute();
  }

  void _recompute() {
    _byProduct = {
      for (final r in RecommendationService.rankProducts(
        products: products,
        context: _ctx,
      ))
        r.product.id: r,
    };
  }

  /// Reloads profile, blacklist and traits (after the Beauty Test, a blacklist
  /// change or an AI classification).
  Future<void> refreshPersonalization() async {
    final userId = _userId;
    if (userId == null) return;
    await _loadPersonalization(userId);
    notifyListeners();
  }

  /// Calls [refreshPersonalization] whenever the profile or the blacklist of
  /// the signed-in user changes.
  void watchProfile({
    required String Function() signature,
    required List<Listenable> sources,
  }) {
    _signatureOf = signature;
    void check() {
      final s = signature();
      if (s == _signature) return;
      _signature = s;
      refreshPersonalization();
    }

    for (final l in sources) {
      l.addListener(check);
    }
  }

  /// AI re-ranking of the top picks (product id -> position); cleared
  /// whenever the profile or the blacklist changes.
  Map<int, int> _aiOrder = {};
  bool get hasAiOrder => _aiOrder.isNotEmpty;

  /// [source] personalized: blacklisted products removed, best match first
  /// (and, after [refineWithAi], in the AI's order for the top picks).
  List<Recommendation> recommend(Iterable<Product> source) {
    final ranked = RecommendationService.rankProducts(
      products: source,
      context: _ctx,
    );
    if (_aiOrder.isEmpty) return ranked;
    final indexed = [for (var i = 0; i < ranked.length; i++) (i, ranked[i])];
    indexed.sort((a, b) {
      final ai = _aiOrder[a.$2.product.id], bi = _aiOrder[b.$2.product.id];
      if (ai != null && bi != null) return ai.compareTo(bi);
      if (ai != null) return -1;
      if (bi != null) return 1;
      return a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2];
  }

  /// Optional AI refinement. The AI only gets products that already passed
  /// the blacklist and local scoring and can only reorder them.
  /// Returns false when the AI is unavailable (the local order stays).
  Future<bool> refineWithAi(RecommendationRefiner refiner) async {
    final local = RecommendationService.rankProducts(
      products: products,
      context: _ctx,
    );
    if (local.length < 2) return true;
    try {
      final order = await refiner.refine(
        profile: _ctx.profile,
        candidates: local,
      );
      _aiOrder = {for (var i = 0; i < order.length; i++) order[i]: i};
      notifyListeners();
      return true;
    } on AiException catch (e) {
      debugPrint('AI ranking skipped: ${e.message}');
      return false;
    }
  }

  /// How many of [source] the personal picks hide because of the age of the
  /// user (retinoids and benzoyl peroxide for a child).
  int hiddenByAge(Iterable<Product> source) {
    final age = _ctx.profile.age;
    if (age == null) return 0;
    return source
        .where((p) => AgeSafety.blocks(age, IngredientCatalog.of(p)))
        .length;
  }

  /// Match info for one product (null when it is blacklisted or unknown).
  Recommendation? recommendationFor(int productId) => _byProduct[productId];

  /// Top personal picks for the Home screen.
  List<Recommendation> recommendedForYou({int limit = 4}) {
    if (!hasProfile) return const [];
    final seen = <String>{};
    return [
      for (final r in recommend(products))
        // one pick per line: the best-matching shade of a palette
        if (r.product.inStock &&
            (shadesOf(r.product).isEmpty || seen.add(lineOf(r.product)!)))
          r,
    ].take(limit).toList();
  }

  /// True when an enabled blacklist item matches this product.
  bool isBlacklisted(int productId) {
    for (final c in _ctx.candidates) {
      if (c.product.id == productId) {
        return RecommendationService.isBlacklisted(c, _ctx.blacklist);
      }
    }
    return false;
  }

  static final _number = RegExp(r'^\d{1,3}$');

  /// The words of a name before its shade number: "Better Than Palette 05
  /// Shade & Shadow Garden" -> "better than palette". Null when the name has
  /// no number (or it is the first word), so such a product has no line.
  static String? lineOf(Product p) {
    final words = p.name.split(' ');
    final at = words.indexWhere(_number.hasMatch);
    if (at < 2) return null;
    return '${p.brand}|${words.sublist(0, at).join(' ').toLowerCase()}';
  }

  /// "05" of "Better Than Palette 05 Shade & Shadow Garden" (null: no number).
  static String? shadeNumber(Product p) {
    for (final w in p.name.split(' ')) {
      if (_number.hasMatch(w)) return w;
    }
    return null;
  }

  /// What is known about the product's line and variant (null: nothing).
  VariantSummary? structureOf(Product p) => structure[p.id];

  /// True for a palette variant: its cells, not a colour dot, tell its colours.
  bool isPalette(Product p) => structure[p.id]?.isPalette ?? false;

  /// All shades of the line the product belongs to (itself included), by
  /// shade number: the palettes 00, 01, 02... of one series. Empty when the
  /// product is alone in its line (a tint with one shade is just a product).
  List<Product> shadesOf(Product p) {
    final line = lineOf(p);
    if (line == null) return const [];
    final all = [
      for (final x in products)
        if (lineOf(x) == line) x,
    ];
    if (all.length < 2) return const [];
    return all..sort((a, b) => shadeNumber(a)!.compareTo(shadeNumber(b)!));
  }

  /// What a list shows as the name: the line ("Better Than Palette") when the
  /// product has several shades, the full name otherwise.
  String listName(Product p) {
    if (shadesOf(p).isEmpty) return p.name;
    final words = p.name.split(' ');
    return words.sublist(0, words.indexWhere(_number.hasMatch)).join(' ');
  }

  /// The shade part of a name: "05 Shade & Shadow Garden".
  static String shadeName(Product p) {
    final words = p.name.split(' ');
    final at = words.indexWhere(_number.hasMatch);
    return at < 0 ? p.name : words.sublist(at).join(' ');
  }

  /// Lists show one tile per line, not one per shade: the first shade of every
  /// line stays (in a personal ranking that is the best-matching one), the
  /// others are picked on the product page.
  List<Product> collapseLines(List<Product> list) {
    final seen = <String>{};
    return [
      for (final p in list)
        if (shadesOf(p).isEmpty || seen.add(lineOf(p)!)) p,
    ];
  }

  List<Product> get featured {
    final list = products.where((p) => p.featured).toList();
    return list.isEmpty ? products.take(4).toList() : list;
  }

  List<Product> get trending => products.where((p) => p.trending).toList();

  List<Product> get favorites => products.where((p) => p.isFavorite).toList();

  Product? byId(int id) {
    for (final p in products) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<List<StorePrice>> storePrices(int productId) =>
      _repo.getStorePrices(productId);

  Future<List<StoreInfo>> stores() => _repo.getStores();

  /// Returns the new favourite state (null on error).
  Future<bool?> toggleFavorite(int productId) async {
    final userId = _userId;
    if (userId == null) return null;
    try {
      final state = await _repo.toggleFavorite(userId, productId);
      products = [
        for (final p in products)
          if (p.id == productId) p.copyWith(isFavorite: state) else p,
      ];
      notifyListeners();
      return state;
    } catch (e) {
      debugPrint('toggleFavorite failed: $e');
      return null;
    }
  }

  Future<void> addHistory(String query) async {
    final userId = _userId;
    if (userId == null || query.trim().isEmpty) return;
    await _repo.addHistory(userId, query);
    history = await _repo.getHistory(userId);
    notifyListeners();
  }

  Future<void> removeHistory(String query) async {
    final userId = _userId;
    if (userId == null) return;
    await _repo.removeHistory(userId, query);
    history = await _repo.getHistory(userId);
    notifyListeners();
  }

  Future<void> clearHistory() async {
    final userId = _userId;
    if (userId == null) return;
    await _repo.clearHistory(userId);
    history = [];
    notifyListeners();
  }
}
