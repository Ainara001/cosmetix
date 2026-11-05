/// What the virtual try-on may show for a catalog product: the kind of product,
/// the shade it is sold in and the COLOUR of that shade, together with where the
/// colour comes from and how far it can be trusted.
///
/// Nothing here is guessed: a colour without a source and a status is refused
/// when the catalog is read, and a product whose colour is not known has the
/// status [TryOnStatus.missing] and no colour, so the app does not offer to try
/// it on. A shade is always a PRODUCT of the catalog (its own id, price, cart and
/// favourite); this record only describes how that product looks on a face.
class TryOnSeed {
  const TryOnSeed({
    required this.kind,
    required this.line,
    required this.shadeCode,
    required this.shadeName,
    required this.colour,
    required this.colourSource,
    required this.colourStatus,
    required this.finish,
    required this.finishSource,
    required this.note,
  });

  /// Product kinds the try-on can show (first stage: lipstick, eyeshadow, blush).
  static const kinds = {'lips', 'eyeshadow', 'blush'};

  /// Where a colour comes from, from the most to the least trustworthy:
  /// * `manufacturer`: given by the manufacturer as a colour value or code;
  /// * `swatch_sampled`: measured on an official swatch picture of THAT shade
  ///   (a photo: depends on its light and screen, so still approximate);
  /// * `legacy_estimate`: the old catalog `shade` value, sampled from the
  ///   product photo or picked by hand by the app developers; NOT data of the
  ///   manufacturer, the packaging does not always match the real colour;
  /// * `missing`: no colour is known.
  static const statuses = {
    TryOnStatus.manufacturer,
    TryOnStatus.swatchSampled,
    TryOnStatus.legacyEstimate,
    TryOnStatus.missing,
  };

  static const finishes = {'matte', 'satin', 'gloss', 'shimmer'};

  final String kind;

  /// Key of the product line (`brand|name before the shade number`), the same
  /// rule the product page uses to group shades; null for a product alone.
  final String? line;

  /// "31" and "Wine Nude" of "Ink The Velvet 31 Wine Nude" (null: the catalog
  /// name does not say).
  final String? shadeCode;
  final String? shadeName;

  /// ARGB, opaque; null when unknown.
  final int? colour;
  final String? colourSource;
  final String colourStatus;

  /// `matte`, `satin`, `gloss`, `shimmer`; null when no source says.
  final String? finish;
  final String? finishSource;

  /// Why something is missing (shown to the team, not to the user).
  final String? note;

  /// The try-on can show this product only when its colour is known.
  bool get canTryOn => colour != null;

  /// The colour is an estimate, not the manufacturer's data: the screen says so.
  bool get isApproximate => colourStatus != TryOnStatus.manufacturer;

  factory TryOnSeed.fromJson(String productKey, Map<String, Object?> j) {
    Never bad(String why) =>
        throw FormatException('products.json: try_on of $productKey: $why');

    String? text(String k) {
      final v = j[k];
      if (v == null) return null;
      if (v is! String) bad('"$k" is not text');
      final t = v.trim();
      return t.isEmpty ? null : t;
    }

    final kind = text('kind');
    if (kind == null || !kinds.contains(kind)) bad('unknown kind "$kind"');
    final status = text('colour_status') ?? TryOnStatus.missing;
    if (!statuses.contains(status)) bad('unknown colour_status "$status"');

    final raw = j['colour'];
    if (raw != null && raw is! int) bad('"colour" is not a number');
    final colour = raw as int?;
    final source = text('colour_source');
    if (colour != null) {
      if (colour >> 24 != 0xFF) {
        bad('the colour must be opaque (ARGB 0xFF......)');
      }
      if (status == TryOnStatus.missing) {
        bad('a colour needs a status other than "missing"');
      }
      if (source == null) bad('a colour needs "colour_source"');
    } else {
      if (status != TryOnStatus.missing) {
        bad('status "$status" without a colour');
      }
      if (source != null) bad('"colour_source" without a colour');
    }

    final finish = text('finish');
    final finishSource = text('finish_source');
    if (finish != null && !finishes.contains(finish)) bad('unknown finish');
    if (finish != null && finishSource == null) bad('a finish needs a source');
    if (finish == null && finishSource != null) bad('a finish source alone');

    return TryOnSeed(
      kind: kind,
      line: text('line'),
      shadeCode: text('shade_code'),
      shadeName: text('shade_name'),
      colour: colour,
      colourSource: source,
      colourStatus: status,
      finish: finish,
      finishSource: finishSource,
      note: text('note'),
    );
  }
}

/// The values of [TryOnSeed.colourStatus].
abstract final class TryOnStatus {
  static const manufacturer = 'manufacturer';
  static const swatchSampled = 'swatch_sampled';
  static const legacyEstimate = 'legacy_estimate';
  static const missing = 'missing';
}
