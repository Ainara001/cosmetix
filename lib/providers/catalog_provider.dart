import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/foundation.dart';

import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/repositories/product_repository.dart';

/// Products, favourites and search history.
class CatalogProvider extends ChangeNotifier {
  CatalogProvider(this._repo);

  final ProductRepository _repo;

  List<Product> products = [];
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
      history = await _repo.getHistory(userId);
    } catch (e) {
      error = tr('Не удалось загрузить каталог');
      debugPrint('catalog load failed: $e');
    }
    loading = false;
    notifyListeners();
  }

  void reset() {
    products = [];
    history = [];
    _userId = null;
    notifyListeners();
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
