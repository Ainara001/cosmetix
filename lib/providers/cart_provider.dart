import 'package:flutter/foundation.dart';

import 'package:cosmetix/models/cart_models.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/repositories/cart_repository.dart';

class CartProvider extends ChangeNotifier {
  CartProvider(this._repo);

  final CartRepository _repo;

  List<CartItem> items = [];
  List<Order> orders = [];
  bool loading = false;
  int? _userId;

  int get count => items.fold(0, (s, i) => s + i.quantity);
  int get total => items.fold(0, (s, i) => s + i.total);
  int get bonus => CartRepository.bonusFor(total);

  bool contains(int productId) => items.any((i) => i.product.id == productId);

  Future<void> load(int userId) async {
    _userId = userId;
    loading = true;
    notifyListeners();
    try {
      items = await _repo.getItems(userId);
      orders = await _repo.getOrders(userId);
    } catch (e) {
      debugPrint('cart load failed: $e');
    }
    loading = false;
    notifyListeners();
  }

  void reset() {
    items = [];
    orders = [];
    _userId = null;
    notifyListeners();
  }

  /// Returns an error message or null when the product was added.
  Future<String?> add(Product product, {int? storeId}) async {
    final userId = _userId;
    if (userId == null) return 'Сначала войдите в аккаунт';
    if (!product.inStock) {
      return 'Товара нет в наличии, добавить его в корзину нельзя';
    }
    try {
      await _repo.add(userId, product.id, storeId);
      items = await _repo.getItems(userId);
      notifyListeners();
      return null;
    } catch (_) {
      return 'Не удалось добавить товар в корзину';
    }
  }

  Future<void> setQuantity(CartItem item, int quantity) async {
    final userId = _userId;
    if (userId == null) return;
    await _repo.setQuantity(item.cartId, quantity);
    items = await _repo.getItems(userId);
    notifyListeners();
  }

  Future<void> remove(CartItem item) => setQuantity(item, 0);

  Future<void> clear() async {
    final userId = _userId;
    if (userId == null) return;
    await _repo.clear(userId);
    items = [];
    notifyListeners();
  }

  /// Creates the order. Returns null when the cart is empty or on error.
  Future<Order?> checkout() async {
    final userId = _userId;
    if (userId == null) return null;
    try {
      final order = await _repo.checkout(userId);
      items = [];
      orders = await _repo.getOrders(userId);
      notifyListeners();
      return order;
    } catch (e) {
      debugPrint('checkout failed: $e');
      return null;
    }
  }

  Future<void> deleteOrder(Order order) async {
    final userId = _userId;
    if (userId == null) return;
    await _repo.deleteOrder(order.id);
    orders = await _repo.getOrders(userId);
    notifyListeners();
  }
}
