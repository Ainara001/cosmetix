import 'dart:ui' show Color;

/// A line of products ("Better Than Palette") whose variants are separate
/// catalog products (see DB v16, `product_lines`).
class ProductLine {
  const ProductLine({
    required this.key,
    required this.slug,
    required this.brand,
    required this.name,
    required this.kind,
    required this.sourceUrl,
    required this.checkedAt,
    required this.confidence,
  });

  final String key;
  final String slug;
  final String brand;

  /// The name of the line without a shade number.
  final String name;

  /// `eyeshadow_palette`, `lips`, ...
  final String kind;
  final String sourceUrl;

  /// ISO date the source was looked at; null when none was recorded.
  final String? checkedAt;
  final String confidence;

  bool get isPalette => kind.endsWith('_palette');
}

/// What a list needs to know about a catalog product in one glance: which line
/// it belongs to, which variant it is and whether it is a palette. Loaded for
/// every product at once (see `CatalogStructureRepository.summaries`).
class VariantSummary {
  const VariantSummary({
    required this.productId,
    required this.lineKey,
    required this.lineName,
    required this.kind,
    required this.code,
    required this.name,
    required this.panCount,
  });

  final int productId;
  final String? lineKey;

  /// The line without a shade number ("Better Than Palette"); null when the
  /// product has no line.
  final String? lineName;

  /// `eyeshadow_palette`, `lips`, `blush`, `eyeshadow` ...
  final String kind;
  final String? code;
  final String? name;

  /// Number of cells a source confirmed; null when it is not established.
  final int? panCount;

  bool get isPalette => kind.endsWith('_palette');
}

/// One variant of a line: a catalog product with its own id, price, cart line
/// and favourite (palette 01, palette 02 ...).
class LineVariant {
  const LineVariant({
    required this.productId,
    required this.code,
    required this.name,
    required this.price,
    required this.inStock,
    required this.panCount,
  });

  final int productId;

  /// "02" (null when the catalog name has no number).
  final String? code;

  /// "Mahogany Garden".
  final String? name;
  final int price;
  final bool inStock;

  /// Number of cells a source confirmed; null when it is not established.
  final int? panCount;
}

/// One cell of a palette. [colour] is null until a source gives it; when it
/// does, [colourStatus] says where it comes from (`measured_swatch` is our own
/// measurement of a physical sample).
class PalettePan {
  const PalettePan({
    required this.key,
    required this.productId,
    required this.position,
    required this.name,
    required this.finish,
    required this.colour,
    required this.colourStatus,
    required this.colourSource,
  });

  /// Stable id of the cell, independent of the product id.
  final String key;
  final int productId;

  /// 1-based number of the cell. It is OUR numbering of the cells of a
  /// palette; it is not claimed to match the physical layout until a
  /// measurement or a photo shows the layout.
  final int position;
  final String? name;
  final String? finish;
  final Color? colour;
  final String colourStatus;
  final String? colourSource;

  /// The try-on may use the cell only when its colour is known.
  bool get canTryOn => colour != null;

  /// Everything but a manufacturer's colour and our own measurement is an
  /// estimate and the screen says so.
  bool get isApproximate =>
      colourStatus != 'manufacturer' && colourStatus != 'measured_swatch';
}

/// What is known about one catalog product that belongs to a line.
class VariantInfo {
  const VariantInfo({
    required this.productId,
    required this.line,
    required this.shadeCode,
    required this.shadeName,
    required this.panCount,
    required this.factsSource,
    required this.factsCheckedAt,
    required this.factsConfidence,
    required this.pans,
  });

  final int productId;
  final ProductLine? line;
  final String? shadeCode;
  final String? shadeName;

  /// Null: the number of cells is not established (no cells exist).
  final int? panCount;
  final String? factsSource;
  final String? factsCheckedAt;
  final String? factsConfidence;
  final List<PalettePan> pans;

  bool get isPalette => pans.isNotEmpty || (line?.isPalette ?? false);

  /// Cells the try-on can use now.
  List<PalettePan> get tryablePans => [
    for (final p in pans)
      if (p.canTryOn) p,
  ];
}
