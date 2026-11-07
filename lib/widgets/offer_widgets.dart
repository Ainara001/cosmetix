import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/models/store_offer.dart';
import 'package:cosmetix/services/source_policy.dart';

/// "dd.MM.yyyy" of an epoch-millisecond time.
String offerDate(int epochMs) {
  final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year}';
}

/// When a shop price was checked. A fresh check says "Проверено", an old one
/// says that the price is the one "at the last check": it is never presented
/// as current.
class OfferCheckedText extends StatelessWidget {
  const OfferCheckedText({
    super.key,
    required this.checkedAt,
    this.now,
    this.compact = false,
  });

  final int? checkedAt;

  /// For tests.
  final DateTime? now;

  /// Shorter words for a narrow place (the price bar): "Цена на 05.11.2026".
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final at = checkedAt;
    if (at == null) return const SizedBox.shrink();
    final age = (now ?? DateTime.now()).difference(
      DateTime.fromMillisecondsSinceEpoch(at),
    );
    final stale = age > StoreOffer.freshFor;
    return Text(
      stale
          ? compact
                ? trf('Цена на {d}', {'d': offerDate(at)})
                : trf('Цена на момент последней проверки: {d}', {
                    'd': offerDate(at),
                  })
          : trf('Проверено {d}', {'d': offerDate(at)}),
      key: Key(stale ? 'offer-stale' : 'offer-fresh'),
      maxLines: compact ? 1 : 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11,
        color: stale ? AppColors.warning : context.pal.subtext,
      ),
    );
  }
}

/// "View the product in the shop": opens the page in the system browser. Shown
/// only for an offer that has a link AND a shop whose conditions allow links
/// (`SourcePolicy`, none by default). A link that opens only a search on the
/// shop's site says so. Cosmetix does not copy the shop's page, photos or
/// design and is not the shop's partner.
class OfferLink extends StatelessWidget {
  const OfferLink({super.key, required this.offer, this.policy});

  final StorePrice offer;

  /// For tests; the bundled policy is read otherwise.
  final SourcePolicy? policy;

  /// For tests: replaces the real launcher.
  static Future<bool> Function(Uri uri) launcher = (uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final url = offer.url;
    if (url == null || offer.urlKind == UrlKind.none) {
      return const SizedBox.shrink();
    }
    Widget button(SourcePolicy p) {
      if (!p.linksAllowed(
        offer.chain.isEmpty ? offer.storeName : offer.chain,
      )) {
        return const SizedBox.shrink();
      }
      final search = offer.urlKind == UrlKind.search;
      return TextButton.icon(
        key: Key('offer-link-${offer.storeId}'),
        onPressed: () {
          final uri = Uri.tryParse(url);
          if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
            launcher(uri);
          }
        },
        icon: const Icon(Icons.open_in_new, size: 16),
        label: Text(
          search ? tr('Поиск в магазине') : tr('Посмотреть товар в магазине'),
        ),
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(48, 36),
          alignment: AlignmentDirectional.centerStart,
          foregroundColor: context.pal.accent,
        ),
      );
    }

    final given = policy;
    if (given != null) return button(given);
    return FutureBuilder<SourcePolicy>(
      future: SourcePolicy.load(),
      builder: (context, snap) =>
          snap.data == null ? const SizedBox.shrink() : button(snap.data!),
    );
  }
}
