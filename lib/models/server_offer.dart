import 'package:cosmetix/models/store_offer.dart';

/// One offer of the server's public snapshot (`GET /v1/catalog/offers`). The
/// product and the shop are named by brand + name and by name + address, not by
/// database ids, so the app can match them with its own rows.
class ServerOffer {
  const ServerOffer({
    required this.brand,
    required this.productName,
    required this.storeName,
    required this.storeAddress,
    required this.city,
    required this.price,
    required this.oldPrice,
    required this.availability,
    required this.url,
    required this.urlKind,
    required this.source,
    required this.method,
    required this.checkedAt,
  });

  final String brand;
  final String productName;
  final String storeName;
  final String storeAddress;
  final String city;
  final int? price;
  final int? oldPrice;
  final Availability availability;
  final String? url;
  final UrlKind urlKind;
  final String source;
  final String method;

  /// When a person checked it (epoch ms).
  final int checkedAt;

  /// Throws a [FormatException] for a row that is not a usable offer: a
  /// snapshot is not trusted blindly.
  factory ServerOffer.fromJson(Map<String, Object?> j) {
    String text(String k) {
      final v = j[k];
      if (v is! String || v.trim().isEmpty) {
        throw FormatException('offer: "$k" is missing');
      }
      return v;
    }

    int? whole(String k) {
      final v = j[k];
      if (v == null) return null;
      if (v is! int || v <= 0) throw FormatException('offer: "$k" is not a price');
      return v;
    }

    final checked = DateTime.tryParse(text('checkedAt'));
    if (checked == null) throw const FormatException('offer: bad checkedAt');
    final url = j['url'];
    return ServerOffer(
      brand: text('brand'),
      productName: text('productName'),
      storeName: text('storeName'),
      storeAddress: text('storeAddress'),
      city: (j['city'] as String?) ?? '',
      price: whole('price'),
      oldPrice: whole('oldPrice'),
      availability: Availability.of(j['availability'] as String?),
      url: url is String && url.isNotEmpty ? url : null,
      urlKind: UrlKind.of(j['urlKind'] as String?),
      source: text('source'),
      method: text('method'),
      checkedAt: checked.millisecondsSinceEpoch,
    );
  }
}
