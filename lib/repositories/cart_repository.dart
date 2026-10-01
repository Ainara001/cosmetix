import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/models/cart_models.dart';

class CartRepository {
  CartRepository(this._helper);

  final DatabaseHelper _helper;

  /// Bonus points = 2% of the order total.
  static int bonusFor(int total) => (total * 0.02).round();

  Future<List<CartItem>> getItems(int userId) async {
    final db = await _helper.database;
    final rows = await db.rawQuery(
      '''
SELECT c.id AS cart_id, c.quantity, c.store_id,
       COALESCE(pp.price, p.price) AS unit_price,
       COALESCE(s.name, '') AS store_name, p.*
FROM cart_items c
JOIN products p ON p.id = c.product_id
LEFT JOIN product_prices pp ON pp.product_id = c.product_id AND pp.store_id = c.store_id
LEFT JOIN stores s ON s.id = c.store_id
WHERE c.user_id = ? ORDER BY c.id DESC''',
      [userId],
    );
    return rows.map(CartItem.fromMap).toList();
  }

  /// Adds a product or increases its quantity (max 10).
  Future<void> add(int userId, int productId, int? storeId) async {
    final db = await _helper.database;
    final existing = await db.query(
      'cart_items',
      where: 'user_id = ? AND product_id = ?',
      whereArgs: [userId, productId],
    );
    if (existing.isEmpty) {
      await db.insert('cart_items', {
        'user_id': userId,
        'product_id': productId,
        'store_id': storeId,
        'quantity': 1,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
    } else {
      final qty = existing.first['quantity'] as int;
      await db.update(
        'cart_items',
        {'quantity': qty >= 10 ? 10 : qty + 1, 'store_id': storeId},
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }
  }

  Future<void> setQuantity(int cartId, int quantity) async {
    final db = await _helper.database;
    if (quantity <= 0) {
      await remove(cartId);
    } else {
      await db.update(
        'cart_items',
        {'quantity': quantity.clamp(1, 10)},
        where: 'id = ?',
        whereArgs: [cartId],
      );
    }
  }

  Future<void> remove(int cartId) async {
    final db = await _helper.database;
    await db.delete('cart_items', where: 'id = ?', whereArgs: [cartId]);
  }

  Future<void> clear(int userId) async {
    final db = await _helper.database;
    await db.delete('cart_items', where: 'user_id = ?', whereArgs: [userId]);
  }

  /// Converts the cart into an order, clears the cart and adds bonus points.
  /// Returns null when the cart is empty.
  Future<Order?> checkout(int userId) async {
    final items = await getItems(userId);
    if (items.isEmpty) return null;
    final db = await _helper.database;
    final total = items.fold<int>(0, (sum, i) => sum + i.total);
    final bonus = bonusFor(total);
    final now = DateTime.now();
    final orderId = await db.transaction((txn) async {
      final id = await txn.insert('orders', {
        'user_id': userId,
        'total': total,
        'bonus': bonus,
        'status': 'Оформлен',
        'created_at': now.millisecondsSinceEpoch,
      });
      for (final i in items) {
        await txn.insert('order_items', {
          'order_id': id,
          'product_id': i.product.id,
          'store_id': i.storeId,
          'quantity': i.quantity,
          'price': i.unitPrice,
        });
      }
      await txn.delete('cart_items', where: 'user_id = ?', whereArgs: [userId]);
      await txn.rawUpdate(
        'UPDATE users SET bonus_points = bonus_points + ? WHERE id = ?',
        [bonus, userId],
      );
      return id;
    });
    return Order(
      id: orderId,
      total: total,
      bonus: bonus,
      status: 'Оформлен',
      createdAt: now,
      lines: [
        for (final i in items)
          OrderLine(
            productId: i.product.id,
            name: i.product.name,
            brand: i.product.brand,
            art: i.product.art,
            color: i.product.color,
            quantity: i.quantity,
            price: i.unitPrice,
          ),
      ],
    );
  }

  Future<List<Order>> getOrders(int userId) async {
    final db = await _helper.database;
    final orderRows = await db.query(
      'orders',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
    );
    final orders = <Order>[];
    for (final o in orderRows) {
      final lines = await db.rawQuery(
        '''
SELECT oi.product_id, oi.quantity, oi.price, p.name, p.brand, p.art, p.color
FROM order_items oi JOIN products p ON p.id = oi.product_id
WHERE oi.order_id = ?''',
        [o['id']],
      );
      orders.add(
        Order(
          id: o['id'] as int,
          total: o['total'] as int,
          bonus: o['bonus'] as int,
          status: o['status'] as String,
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            o['created_at'] as int,
          ),
          lines: lines.map(OrderLine.fromMap).toList(),
        ),
      );
    }
    return orders;
  }

  Future<void> deleteOrder(int orderId) async {
    final db = await _helper.database;
    await db.delete('orders', where: 'id = ?', whereArgs: [orderId]);
  }
}
