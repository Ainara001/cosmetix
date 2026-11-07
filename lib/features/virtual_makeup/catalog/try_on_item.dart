import 'dart:ui' show Color;

import 'package:cosmetix/core/i18n/tr.dart';

import '../domain/makeup_look.dart';

/// Three different things, never mixed up:
///  * the PRODUCT the shop sells (a row of the catalog with its own id, price,
///    cart line and favourite; every shade is such a product),
///  * the SHADE it is sold in (code and name, e.g. "31 Wine Nude"),
///  * the COLOUR the try-on paints ([colour], an estimate with a [status]).
///
/// This class is what the try-on needs to know about one product.
class TryOnItem {
  const TryOnItem({
    required this.productId,
    required this.brand,
    required this.name,
    required this.kind,
    required this.lineKey,
    required this.shadeCode,
    required this.shadeName,
    required this.colour,
    required this.colourSource,
    required this.status,
    required this.finish,
    required this.photo,
    required this.price,
    required this.inStock,
    this.panKey,
    this.panPosition,
  });

  /// The catalog product (and the shade: one product is one shade).
  final int productId;
  final String brand;

  /// Full product name as the catalog has it.
  final String name;
  final MakeupZone kind;

  /// Shades of one line share this key (null: the product is alone).
  final String? lineKey;
  final String? shadeCode;
  final String? shadeName;

  /// Null when the catalog does not know the colour: not offered for try-on.
  final Color? colour;
  final String? colourSource;

  /// `manufacturer`, `swatch_sampled`, `legacy_estimate` or `missing`.
  final String status;

  /// `matte`, `satin`, `gloss`, `shimmer` or null (no source says).
  final String? finish;

  /// Photo of the PACKAGE (an asset path), not of the shade; null if none.
  final String? photo;
  final int price;
  final bool inStock;

  /// Set when this item is ONE CELL of a palette product: the id of the cell
  /// and its number. The colour is then the colour of that cell (only cells
  /// whose colour is known become items); [productId] is still the palette.
  final String? panKey;
  final int? panPosition;

  /// "Ячейка 3" for a cell of a palette, null for any other item.
  String? get cellLabel =>
      panPosition == null ? null : trf('Ячейка {n}', {'n': panPosition});

  bool get canTryOn => colour != null;

  /// The colour is not the manufacturer's own value: the screen says so.
  bool get isApproximate =>
      status != 'manufacturer' && status != 'measured_swatch';

  /// The product name without the shade it ends with: "Ink Mood Glowy Tint 30
  /// Happy Berry" -> "Ink Mood Glowy Tint". The full [name] when the shade is not
  /// at its end.
  String get lineName {
    final shade = shadeLabel;
    if (shade != null && name.endsWith(' $shade')) {
      return name.substring(0, name.length - shade.length - 1);
    }
    return name;
  }

  /// "31 Wine Nude", "Wine Nude", "31" or null when the catalog gives no shade.
  String? get shadeLabel {
    final parts = [shadeCode, shadeName].whereType<String>().toList();
    return parts.isEmpty ? null : parts.join(' ');
  }

  @override
  bool operator ==(Object other) =>
      other is TryOnItem &&
      other.productId == productId &&
      other.panKey == panKey;

  @override
  int get hashCode => Object.hash(productId, panKey);
}

/// Where the try-on gets its products. The app implements it with the local
/// SQLite catalog (works without a network); tests use a fake.
abstract interface class TryOnCatalog {
  /// The try-on record of a product, or null when it has none. The item may
  /// have no colour ([TryOnItem.canTryOn] false).
  Future<TryOnItem?> item(int productId);

  /// Shades of the same line and kind that can be tried on (the item itself
  /// included), by shade code. Empty when the item is alone in its line.
  Future<List<TryOnItem>> sameLine(TryOnItem item);

  /// Other products of the kind that can be tried on, not of the item's line.
  Future<List<TryOnItem>> otherProducts(TryOnItem item);

  /// Every product of a kind that can be tried on.
  Future<List<TryOnItem>> all(MakeupZone kind);
}
