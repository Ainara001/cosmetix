import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/foundation.dart';

import 'package:cosmetix/models/cart_models.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/repositories/cart_repository.dart';

class CartProvider extends ChangeNotifier {
  CartProvider(this._repo);

  final CartRepository _repo;

  /// Why a product must not be sold to this user (their age), or null. Set
  /// by the app, which knows the signed-in user.
  String? Function(Product product)? guard;

  List<CartItem> items = [];
  List<Order> orders = [];
  bool loading = false;
  int? _userId;

  /// Bonus points the user owns and whether they are spent on this cart.
  int bonusBalance = 0;
  bool useBonus = false;

  int get count => items.fold(0, (s, i) => s + i.quantity);

  /// Cart value before the bonus discount.
  int get total => items.fold(0, (s, i) => s + i.total);

  /// Points that would be spent (0 while the switch is off).
  int get bonusToSpend =>
      useBonus ? CartRepository.spendable(bonusBalance, total) : 0;

  /// What the user pays after the bonus discount.
  int get payable => total - bonusToSpend;

  /// Points earned by this order (2% of [payable]).
  int get bonus => CartRepository.bonusFor(payable);

  /// Points that could be spent on this cart right now.
  int get spendableBonus => CartRepository.spendable(bonusBalance, total);

  void setUseBonus(bool value) {
    useBonus = value;
    notifyListeners();
  }

  bool contains(int productId) => items.any((i) => i.product.id == productId);

  /// How many pieces of a product are in the cart (all shops together).
  int quantityOf(int productId) => items
      .where((i) => i.product.id == productId)
      .fold(0, (s, i) => s + i.quantity);

  /// Takes one piece of a product out of the cart; the line disappears at 0.
  Future<void> decrease(int productId) async {
    final lines = items.where((i) => i.product.id == productId);
    if (lines.isEmpty) return;
    await setQuantity(lines.last, lines.last.quantity - 1);
  }

  Future<void> load(int userId) async {
    _userId = userId;
    loading = true;
    notifyListeners();
    try {
      items = await _repo.getItems(userId);
      orders = await _repo.getOrders(userId);
      bonusBalance = await _repo.bonusBalance(userId);
    } catch (e) {
      debugPrint('cart load failed: $e');
    }
    loading = false;
    notifyListeners();
  }

  void reset() {
    items = [];
    orders = [];
    bonusBalance = 0;
    useBonus = false;
    _userId = null;
    notifyListeners();
  }

  /// Returns an error message or null when the product was added.
  Future<String?> add(Product product, {int? storeId}) async {
    final userId = _userId;
    if (userId == null) return tr('Сначала войдите в аккаунт');
    if (!product.inStock) {
      return tr('Товара нет в наличии, добавить его в корзину нельзя');
    }
    final blocked = guard?.call(product);
    if (blocked != null) return tr(blocked);
    try {
      await _repo.add(userId, product.id, storeId);
      items = await _repo.getItems(userId);
      notifyListeners();
      return null;
    } catch (_) {
      return tr('Не удалось добавить товар в корзину');
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
      final order = await _repo.checkout(userId, useBonus: bonusToSpend);
      items = [];
      useBonus = false;
      orders = await _repo.getOrders(userId);
      bonusBalance = await _repo.bonusBalance(userId);
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
    bonusBalance = await _repo.bonusBalance(userId);
    notifyListeners();
  }
}
