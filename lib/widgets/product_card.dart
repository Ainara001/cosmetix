import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/providers/catalog_provider.dart';
import 'package:cosmetix/providers/settings_provider.dart';
import 'product_art.dart';

/// The tile of a product in a list: for a product with several shades it is
/// the tile of the whole line (name of the line, a dot per shade).
ProductCard lineCard(
  CatalogProvider catalog,
  Product p, {
  required VoidCallback onTap,
  VoidCallback? onFavorite,
  Widget? footer,
}) {
  final shades = catalog.shadesOf(p);
  final palette = catalog.isPalette(p);
  final cells = catalog.structureOf(p)?.panCount;
  return ProductCard(
    product: p,
    title: shades.isEmpty ? null : catalog.listName(p),
    // a palette is told by its number of variants and cells, not by one colour
    // dot per variant (those dots were estimates of the pack colour)
    subtitle: shades.isEmpty
        ? null
        : palette
        ? [
            trf('Вариантов: {n}', {'n': shades.length}),
            if (cells != null) trf('цветов: {n}', {'n': cells}),
          ].join(' · ')
        : trf('Оттенков: {n}', {'n': shades.length}),
    shades: palette
        ? const []
        : [for (final s in shades) Color(s.shade ?? s.color)],
    footer: footer,
    onTap: onTap,
    onFavorite: onFavorite,
  );
}

/// Product tile used in the catalog, home, cart and search results.
class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.onFavorite,
    this.priceOverride,
    this.footer,
    this.title,
    this.subtitle,
    this.shades = const [],
  });

  final Product product;
  final VoidCallback onTap;

  /// When set, a heart button is shown in the corner.
  final VoidCallback? onFavorite;

  /// Price from a concrete store (cart); the product price is used otherwise.
  final int? priceOverride;
  final Widget? footer;

  /// Shown instead of the product name (the line of a product with shades).
  final String? title;

  /// A second, quieter line under the name ("Вариантов: 6 · цветов: 10").
  final String? subtitle;

  /// Colours of all shades of the line: small dots on the photo.
  final List<Color> shades;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final fmt = context.watch<SettingsProvider>().priceText;
    final price = priceOverride ?? product.price;
    final sale = product.hasDiscount && priceOverride == null;

    return Material(
      color: pal.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: pal.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ProductArt(art: product.art, color: product.color),
                    ),
                    if (sale)
                      Positioned(
                        left: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.sale,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '-${product.discountPercent}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    if (shades.isNotEmpty)
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: _ShadeDots(colors: shades),
                      ),
                    if (!product.inStock)
                      Positioned(
                        left: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: pal.text.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            tr('Нет в наличии'),
                            style: TextStyle(color: pal.surface, fontSize: 10),
                          ),
                        ),
                      ),
                    if (onFavorite != null)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: InkWell(
                          onTap: onFavorite,
                          customBorder: const CircleBorder(),
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: pal.surface.withValues(alpha: 0.9),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              product.isFavorite
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              size: 17,
                              color: context.pal.accent,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.brand,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: pal.subtext),
                    ),
                    // the name and the quiet line under it are always three
                    // lines tall together (long names such as "Better Than
                    // Palette 05 Shade & Shadow Garden" are not cut in the
                    // middle of a word), so the photos in a row match
                    SizedBox(
                      height: MediaQuery.textScalerOf(
                        context,
                      ).scale(12.5 * 1.2 * (subtitle == null ? 3 : 2)),
                      child: Text(
                        tr(title ?? product.name),
                        maxLines: subtitle == null ? 3 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                    ),
                    if (subtitle != null)
                      SizedBox(
                        height: MediaQuery.textScalerOf(
                          context,
                        ).scale(11 * 1.2),
                        child: Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.2,
                            color: pal.subtext,
                          ),
                        ),
                      ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          fmt(price),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: sale ? AppColors.sale : pal.text,
                          ),
                        ),
                        if (sale)
                          Text(
                            fmt(product.oldPrice!),
                            style: TextStyle(
                              fontSize: 10,
                              color: pal.subtext,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                      ],
                    ),
                    if (footer != null) ...[const SizedBox(height: 4), footer!],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Grid delegate with a fixed card height (grows with the system font size,
/// so the text block never overflows).
SliverGridDelegate productGridDelegate(
  BuildContext context, {
  double extent = 250,
}) => SliverGridDelegateWithFixedCrossAxisCount(
  crossAxisCount: 2,
  mainAxisSpacing: 12,
  crossAxisSpacing: 12,
  mainAxisExtent: extent + MediaQuery.textScalerOf(context).scale(100) - 100,
);

/// A row of small colour dots (the shades of a line) on a product photo.
class _ShadeDots extends StatelessWidget {
  const _ShadeDots({required this.colors});

  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    const max = 5;
    final shown = colors.take(max).toList();
    final more = colors.length - shown.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: pal.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: pal.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in shown)
            Container(
              width: 11,
              height: 11,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(color: pal.border, width: 0.5),
              ),
            ),
          if (more > 0)
            Padding(
              padding: const EdgeInsets.only(left: 3),
              child: Text(
                '+$more',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: pal.subtext,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
