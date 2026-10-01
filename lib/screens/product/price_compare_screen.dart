import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/providers/cart_provider.dart';
import 'package:cosmetix/providers/catalog_provider.dart';
import 'package:cosmetix/providers/settings_provider.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/common_widgets.dart';
import 'package:cosmetix/widgets/custom_button.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';
import 'package:cosmetix/widgets/product_art.dart';

class PriceCompareScreen extends StatefulWidget {
  const PriceCompareScreen({super.key, required this.productId});

  final int productId;

  @override
  State<PriceCompareScreen> createState() => _PriceCompareScreenState();
}

class _PriceCompareScreenState extends State<PriceCompareScreen> {
  List<StorePrice> _prices = [];
  bool _cheapFirst = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    context
        .read<CatalogProvider>()
        .storePrices(widget.productId)
        .then((v) {
          if (mounted) {
            setState(() {
              _prices = v;
              _loading = false;
            });
          }
        })
        .catchError((_) {
          if (mounted) setState(() => _loading = false);
        });
  }

  Future<void> _openStore(Product product, StorePrice p) async {
    final fmt = context.read<SettingsProvider>().priceText;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.storeName, style: AppTextStyles.h2),
            const SizedBox(height: 4),
            Text('${p.address} • ${p.distanceLabel}'),
            const SizedBox(height: 4),
            Text('Рейтинг магазина: ★ ${p.rating}'),
            const SizedBox(height: 12),
            Text(
              '${product.name} — ${fmt(p.price)}',
              style: AppTextStyles.bodyBold,
            ),
            const SizedBox(height: 16),
            CustomButton(
              label: p.inStock
                  ? 'Добавить в корзину из этого магазина'
                  : 'Нет в наличии',
              onPressed: p.inStock
                  ? () async {
                      Navigator.pop(ctx);
                      final err = await context.read<CartProvider>().add(
                        product,
                        storeId: p.storeId,
                      );
                      if (!mounted) return;
                      showMessage(
                        context,
                        err ?? 'Добавлено в корзину: ${p.storeName}',
                        type: err == null
                            ? MessageType.success
                            : MessageType.error,
                      );
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final product = context.watch<CatalogProvider>().byId(widget.productId);
    final pal = context.pal;
    final fmt = context.watch<SettingsProvider>().priceText;

    if (product == null) {
      return PageScaffold(
        title: 'Сравнение цен',
        child: const EmptyState(
          icon: Icons.search_off,
          title: 'Товар не найден',
        ),
      );
    }

    final list = [..._prices]
      ..sort(
        (a, b) => _cheapFirst
            ? a.price.compareTo(b.price)
            : a.distanceM.compareTo(b.distanceM),
      );
    final best = _prices.isEmpty
        ? product.price
        : _prices.map((e) => e.price).reduce((a, b) => a < b ? a : b);

    return PageScaffold(
      title: 'Сравнение цен',
      bigTitle: true,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                AppCard(
                  child: Row(
                    children: [
                      SizedBox(
                        width: 48,
                        height: 40,
                        child: ProductArt(
                          art: product.art,
                          color: product.color,
                          radius: 8,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodyBold,
                            ),
                            Text(
                              'Лучшая цена: от ${fmt(best)}',
                              style: AppTextStyles.small.copyWith(
                                color: pal.subtext,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AppChip(
                      label: 'Сначала дешёвые',
                      selected: _cheapFirst,
                      onTap: () => setState(() => _cheapFirst = true),
                    ),
                    AppChip(
                      label: 'Ближе ко мне',
                      selected: !_cheapFirst,
                      onTap: () => setState(() => _cheapFirst = false),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (list.isEmpty)
                  const EmptyState(
                    icon: Icons.storefront_outlined,
                    title: 'Нет предложений',
                    subtitle: 'Для этого товара пока нет цен в магазинах',
                  )
                else
                  for (final p in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AppCard(
                        onTap: () => _openStore(product, p),
                        borderColor: p.price == best && p.inStock
                            ? AppColors.primaryDark
                            : null,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    p.storeName,
                                    style: AppTextStyles.subtitle,
                                  ),
                                ),
                                Text(
                                  fmt(p.price),
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: p.price == best && p.inStock
                                        ? AppColors.sale
                                        : pal.text,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(
                                  Icons.place,
                                  size: 13,
                                  color: AppColors.primaryDark,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '${p.distanceLabel} • ${p.address}',
                                    style: AppTextStyles.caption.copyWith(
                                      color: pal.subtext,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.successSoft,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    '★ ${p.rating}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.success,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (!p.inStock)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Нет в наличии',
                                  style: AppTextStyles.caption.copyWith(
                                    color: AppColors.sale,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
    );
  }
}
