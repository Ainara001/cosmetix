import 'dart:convert';

import 'package:cosmetix/database/catalog_data.dart';

/// How far a fact about a line or a variant can be trusted, from the most to
/// the least. Written next to the source and the check date; never guessed.
abstract final class FactConfidence {
  /// The manufacturer's own page, read and checked by hand.
  static const officialPage = 'official_page';

  /// The manufacturer's own page, read through a page-reading tool and not yet
  /// checked by hand.
  static const officialPageUnchecked = 'official_page_unchecked';

  /// A third party (INCIDecoder, a retailer).
  static const thirdParty = 'third_party';

  /// Sources disagree or none was found.
  static const unconfirmed = 'unconfirmed';

  static const all = {
    officialPage,
    officialPageUnchecked,
    thirdParty,
    unconfirmed,
  };
}

/// The values of a pan colour status (the same words as `TryOnStatus`, plus the
/// one our own measurement will use). `measured_swatch` is NEVER written by the
/// catalog files: it can only come from a measurement made with physical
/// samples.
abstract final class PanColourStatus {
  static const manufacturer = 'manufacturer';
  static const swatchSampled = 'swatch_sampled';
  static const legacyEstimate = 'legacy_estimate';
  static const measuredSwatch = 'measured_swatch';
  static const missing = 'missing';

  static const all = {
    manufacturer,
    swatchSampled,
    legacyEstimate,
    measuredSwatch,
    missing,
  };
}

/// One line of products ("Better Than Palette"): the shared name of variants
/// that are sold as separate products (01, 02 ...).
class LineSeed {
  const LineSeed({
    required this.key,
    required this.slug,
    required this.brand,
    required this.name,
    required this.kind,
    required this.sourceUrl,
    required this.checkedAt,
    required this.confidence,
    required this.note,
  });

  /// `brand|name before the shade number, lower case`: the same key as
  /// `product_shades.line_key`.
  final String key;

  /// Stable ASCII word for the ids of the cells (`romand-better-than-palette`).
  final String slug;
  final String brand;
  final String name;

  /// `eyeshadow_palette`, `lips`, ...
  final String kind;
  final String sourceUrl;

  /// ISO date (`2026-11-05`) the source was looked at; null when no date was
  /// recorded.
  final String? checkedAt;
  final String confidence;
  final String? note;

  factory LineSeed.fromJson(Map<String, Object?> j) {
    String str(String k) {
      final v = j[k];
      if (v is! String || v.trim().isEmpty) {
        throw FormatException('lines.json: line "${j['key']}": "$k" missing');
      }
      return v.trim();
    }

    final slug = str('slug');
    if (!RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(slug)) {
      throw FormatException('lines.json: slug "$slug" is not lower-case ASCII');
    }
    return LineSeed(
      key: str('key'),
      slug: slug,
      brand: str('brand'),
      name: str('name'),
      kind: str('kind'),
      sourceUrl: _source(str('source_url'), 'line "${j['key']}"'),
      checkedAt: _date(j['checked_at'], 'line "${j['key']}"'),
      confidence: _confidence(str('confidence'), 'line "${j['key']}"'),
      note: _text(j['note']),
    );
  }
}

/// What is known about one variant (one catalog product) of a line: how many
/// cells a palette has, where that comes from, when it was looked at.
class VariantFactsSeed {
  const VariantFactsSeed({
    required this.productKey,
    required this.panCount,
    required this.sourceUrl,
    required this.checkedAt,
    required this.confidence,
    required this.note,
  });

  /// `brand|name` of the catalog product.
  final String productKey;

  /// Number of cells; null when it is not established (then no cells exist).
  final int? panCount;
  final String sourceUrl;
  final String? checkedAt;
  final String confidence;
  final String? note;

  factory VariantFactsSeed.fromJson(Map<String, Object?> j) {
    final product = j['product'];
    if (product is! String || product.isEmpty) {
      throw const FormatException('lines.json: a variant without "product"');
    }
    final count = j['pan_count'];
    if (count != null && (count is! int || count < 1 || count > 64)) {
      throw FormatException('lines.json: pan_count of $product is not 1..64');
    }
    final source = j['source_url'];
    if (source is! String) {
      throw FormatException('lines.json: $product has no source_url');
    }
    final confidence = _confidence((j['confidence'] as String?) ?? '', product);
    // a number of cells that nobody confirmed would be a guess
    if (count != null && confidence == FactConfidence.unconfirmed) {
      throw FormatException(
        'lines.json: $product: a pan_count needs a confidence above unconfirmed',
      );
    }
    return VariantFactsSeed(
      productKey: product,
      panCount: count as int?,
      sourceUrl: _source(source, product),
      checkedAt: _date(j['checked_at'], product),
      confidence: confidence,
      note: _text(j['note']),
    );
  }
}

/// `assets/catalog/lines.json`: product lines and the facts about their
/// variants. Read with [load]; checked against the product catalog by
/// [validateAgainst].
class CatalogStructure {
  CatalogStructure({required this.lines, required this.variants}) {
    final keys = <String>{};
    final slugs = <String>{};
    for (final l in lines) {
      if (!keys.add(l.key)) {
        throw FormatException('lines.json: line ${l.key} is listed twice');
      }
      if (!slugs.add(l.slug)) {
        throw FormatException('lines.json: slug ${l.slug} is used twice');
      }
    }
    final products = <String>{};
    for (final v in variants) {
      if (!products.add(v.productKey)) {
        throw FormatException('lines.json: ${v.productKey} is listed twice');
      }
    }
  }

  static const asset = 'assets/catalog/lines.json';

  final List<LineSeed> lines;
  final List<VariantFactsSeed> variants;

  Map<String, LineSeed> get lineByKey => {for (final l in lines) l.key: l};

  factory CatalogStructure.parse(String json) {
    final j = jsonDecode(json);
    if (j is! Map || j['lines'] is! List || j['variants'] is! List) {
      throw const FormatException('lines.json: needs "lines" and "variants"');
    }
    return CatalogStructure(
      lines: [
        for (final e in j['lines'] as List)
          LineSeed.fromJson((e as Map).cast()),
      ],
      variants: [
        for (final e in j['variants'] as List)
          VariantFactsSeed.fromJson((e as Map).cast()),
      ],
    );
  }

  /// Every product named here exists, and every `line` a product points to in
  /// `try_on` is a line of this file. Throws a [FormatException] otherwise.
  void validateAgainst(CatalogData catalog) {
    final byKey = catalog.byKey;
    for (final v in variants) {
      if (!byKey.containsKey(v.productKey)) {
        throw FormatException('lines.json: no catalog product ${v.productKey}');
      }
    }
    final known = lineByKey;
    for (final p in catalog.products) {
      final line = p.tryOn?.line;
      if (line != null && !known.containsKey(line)) {
        throw FormatException(
          'lines.json: ${p.key} points to the line "$line", which is not listed',
        );
      }
    }
  }

  static CatalogStructure? _cache;

  /// Reads the file once per run, in the same way as [CatalogData.load].
  static Future<CatalogStructure> load([
    Future<String> Function(String path)? reader,
  ]) async {
    if (reader == null && _cache != null) return _cache!;
    final read = reader ?? CatalogData.assetReader;
    final data = CatalogStructure.parse(await read(asset));
    if (reader == null) _cache = data;
    return data;
  }
}

/// The id of a cell: stable text that does not depend on the order of the rows
/// or on the product id, so a measurement made later keeps pointing at it.
/// `romand-better-than-palette/02/07` = line, variant code, cell 7.
String panKeyOf(String lineSlug, String variantCode, int position) =>
    '$lineSlug/${variantCode.toLowerCase()}/${position.toString().padLeft(2, '0')}';

String? _text(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

String _source(String v, String owner) {
  final uri = Uri.tryParse(v);
  if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
    throw FormatException('lines.json: $owner: source_url is not a link');
  }
  return v;
}

String? _date(Object? v, String owner) {
  if (v == null) return null;
  if (v is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v)) {
    throw FormatException('lines.json: $owner: checked_at is not YYYY-MM-DD');
  }
  return v;
}

String _confidence(String v, String owner) {
  if (!FactConfidence.all.contains(v)) {
    throw FormatException('lines.json: $owner: unknown confidence "$v"');
  }
  return v;
}
