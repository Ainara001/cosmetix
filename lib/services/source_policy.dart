import 'dart:convert';

import 'package:cosmetix/database/catalog_data.dart';

/// What the app may do with a shop's data (`assets/catalog/source_policy.json`).
/// Links to a shop's product pages are shown only when the policy says
/// `allowed` for that shop; the default for every shop is "not confirmed", so
/// nothing is shown until a basis has been recorded.
class SourcePolicy {
  const SourcePolicy._(this._linksByShop, this._defaultLinks);

  final Map<String, String> _linksByShop;
  final String _defaultLinks;

  static const asset = 'assets/catalog/source_policy.json';

  /// For tests and for a build that has recorded a basis for some shops.
  const SourcePolicy.of(
    Map<String, String> links, {
    String defaultLinks = 'unconfirmed',
  }) : this._(links, defaultLinks);

  factory SourcePolicy.parse(String json) {
    final j = jsonDecode(json) as Map<String, Object?>;
    final shops = (j['shops'] as Map?)?.cast<String, Object?>() ?? const {};
    final def = (j['default'] as Map?)?.cast<String, Object?>() ?? const {};
    return SourcePolicy._({
      for (final e in shops.entries)
        e.key: ((e.value as Map)['links'] as String?) ?? 'unconfirmed',
    }, (def['links'] as String?) ?? 'unconfirmed');
  }

  /// A link to this shop's product page may be shown.
  bool linksAllowed(String shopOrChain) =>
      (_linksByShop[shopOrChain] ?? _defaultLinks) == 'allowed';

  static SourcePolicy? _cache;

  static Future<SourcePolicy> load() async {
    return _cache ??= SourcePolicy.parse(await CatalogData.assetReader(asset));
  }
}
