import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/providers/settings_provider.dart';
import 'product_art.dart';

/// Product tile used in the catalog, home, cart and search results.
class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.onFavorite,
    this.priceOverride,
    this.footer,
  });

  final Product product;
  final VoidCallback onTap;

  /// When set, a heart button is shown in the corner.
  final VoidCallback? onFavorite;

  /// Price from a concrete store (cart); the product price is used otherwise.
  final int? priceOverride;
  final Widget? footer;

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
                              color: AppColors.primaryDark,
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
                    // always two lines tall, so the photos in a row match
                    SizedBox(
                      height: MediaQuery.textScalerOf(
                        context,
                      ).scale(12.5 * 1.2 * 2),
                      child: Text(
                        tr(product.name),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
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
