import 'package:cosmetix/models/product.dart';

class CartItem {
  const CartItem({
    required this.cartId,
    required this.product,
    required this.storeId,
    required this.storeName,
    required this.unitPrice,
    required this.quantity,
  });

  final int cartId;
  final Product product;
  final int? storeId;
  final String storeName;
  final int unitPrice;
  final int quantity;

  int get total => unitPrice * quantity;

  factory CartItem.fromMap(Map<String, Object?> m) => CartItem(
    cartId: m['cart_id'] as int,
    product: Product.fromMap(m),
    storeId: m['store_id'] as int?,
    storeName: m['store_name'] as String? ?? '',
    unitPrice: m['unit_price'] as int,
    quantity: m['quantity'] as int,
  );
}

class OrderLine {
  const OrderLine({
    required this.name,
    required this.brand,
    required this.art,
    required this.color,
    required this.quantity,
    required this.price,
    required this.productId,
  });

  final int productId;
  final String name;
  final String brand;
  final String art;
  final int color;
  final int quantity;
  final int price;

  factory OrderLine.fromMap(Map<String, Object?> m) => OrderLine(
    productId: m['product_id'] as int,
    name: m['name'] as String,
    brand: m['brand'] as String,
    art: m['art'] as String? ?? 'bottle',
    color: m['color'] as int? ?? 0xFFF4B6C2,
    quantity: m['quantity'] as int,
    price: m['price'] as int,
  );
}

class Order {
  const Order({
    required this.id,
    required this.total,
    required this.bonus,
    required this.status,
    required this.createdAt,
    required this.lines,
  });

  final int id;
  final int total;
  final int bonus;
  final String status;
  final DateTime createdAt;
  final List<OrderLine> lines;
}
