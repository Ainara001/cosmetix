import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/providers/catalog_provider.dart';
import 'package:cosmetix/providers/settings_provider.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/widgets/product_art.dart';

/// A small tappable product card (chat answers, colour-test result). Tapping
/// opens the product page. [note] is an optional line under the price, for
/// example why the product suits the person.
class ProductMiniCard extends StatelessWidget {
  const ProductMiniCard({super.key, required this.productId, this.note});

  final int productId;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final Product? p = context.watch<CatalogProvider>().byId(productId);
    // an id the model made up (or a product that is gone) shows nothing
    if (p == null) return const SizedBox.shrink();
    final pal = context.pal;
    final price = context.watch<SettingsProvider>().priceText(p.price);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: AppColors.blush,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () =>
              Navigator.pushNamed(context, AppRoutes.product, arguments: p.id),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  height: 52,
                  child: ProductArt(art: p.art, color: p.color, radius: 8),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.brand,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: pal.subtext),
                      ),
                      Text(
                        tr(p.name),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      Text(
                        price,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: p.hasDiscount ? AppColors.sale : pal.text,
                        ),
                      ),
                      if (note != null)
                        Text(
                          note!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: context.pal.accent,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: context.pal.accent,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
