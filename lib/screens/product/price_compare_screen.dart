import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/providers/cart_provider.dart';
import 'package:cosmetix/providers/catalog_provider.dart';
import 'package:cosmetix/providers/location_provider.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/routes/route_args.dart';
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
            Text(tr(p.storeName), style: AppTextStyles.h2),
            const SizedBox(height: 4),
            Text('${tr(p.address)} • ${p.distanceLabel}'),
            const SizedBox(height: 4),
            if (p.rating > 0)
              Text(trf('Рейтинг магазина: ★ {v0}', {'v0': p.rating})),
            if (p.hours.isNotEmpty)
              Text(
                '${p.hours} • ${p.openStatus(DateTime.now())}',
                style: AppTextStyles.small,
              ),
            const SizedBox(height: 12),
            Text(
              '${tr(product.name)} — ${fmt(p.price)}',
              style: AppTextStyles.bodyBold,
            ),
            const SizedBox(height: 16),
            CustomButton(
              label: p.inStock
                  ? tr('Добавить в корзину из этого магазина')
                  : tr('Нет в наличии'),
              onPressed: () async {
                if (!p.inStock) {
                  showMessage(
                    ctx,
                    trf(
                      'В магазине «{v0}» товара нет в наличии. Выберите другой магазин.',
                      {'v0': tr(p.storeName)},
                    ),
                    type: MessageType.warning,
                  );
                  return;
                }
                Navigator.pop(ctx);
                final err = await context.read<CartProvider>().add(
                  product,
                  storeId: p.storeId,
                );
                if (!mounted) return;
                showMessage(
                  context,
                  err ??
                      trf('Добавлено в корзину: {v0}', {'v0': tr(p.storeName)}),
                  type: err == null ? MessageType.success : MessageType.error,
                );
              },
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
        title: tr('Сравнение цен'),
        child: EmptyState(icon: Icons.search_off, title: tr('Товар не найден')),
      );
    }

    final loc = context.watch<LocationProvider>();
    final prices = [
      for (final p in _prices)
        p.hasPosition ? p.withDistance(loc.distanceTo(p.lat!, p.lng!)) : p,
    ];
    final list = [...prices]
      ..sort(
        (a, b) => _cheapFirst
            ? a.price.compareTo(b.price)
            : a.distanceM.compareTo(b.distanceM),
      );
    final best = prices.where((e) => e.inStock).isEmpty
        ? product.price
        : prices
              .where((e) => e.inStock)
              .map((e) => e.price)
              .reduce((a, b) => a < b ? a : b);

    return PageScaffold(
      title: tr('Сравнение цен'),
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
                              tr(product.name),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodyBold,
                            ),
                            Text(
                              trf('Лучшая цена: от {v0}', {'v0': fmt(best)}),
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
                CustomButton(
                  label: tr('Показать на карте'),
                  icon: Icons.map_outlined,
                  outlined: true,
                  onPressed: () => Navigator.pushNamed(
                    context,
                    AppRoutes.stores,
                    arguments: StoresArgs(productId: product.id),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AppChip(
                      label: tr('Сначала дешёвые'),
                      selected: _cheapFirst,
                      onTap: () => setState(() => _cheapFirst = true),
                    ),
                    AppChip(
                      label: tr('Ближе ко мне'),
                      selected: !_cheapFirst,
                      onTap: () => setState(() => _cheapFirst = false),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (list.isEmpty)
                  EmptyState(
                    icon: Icons.storefront_outlined,
                    title: tr('Нет предложений'),
                    subtitle: tr('Для этого товара пока нет цен в магазинах'),
                  )
                else
                  for (final p in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AppCard(
                        onTap: () => _openStore(product, p),
                        borderColor: p.price == best && p.inStock
                            ? context.pal.accent
                            : null,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    tr(p.storeName),
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
                                  color: context.pal.accent,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '${p.distanceLabel} • ${tr(p.address)}',
                                    style: AppTextStyles.caption.copyWith(
                                      color: pal.subtext,
                                    ),
                                  ),
                                ),
                                if (p.rating > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: context.pal.greenSoft,
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
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                switch (p.level) {
                                  StockLevel.out => tr('Нет в наличии'),
                                  StockLevel.low => trf('Мало · {v0} шт.', {
                                    'v0': p.qty,
                                  }),
                                  StockLevel.inStock =>
                                    p.qty == null
                                        ? tr('В наличии')
                                        : trf('В наличии · {v0} шт.', {
                                            'v0': p.qty,
                                          }),
                                },
                                style: AppTextStyles.caption.copyWith(
                                  color: switch (p.level) {
                                    StockLevel.out => AppColors.sale,
                                    StockLevel.low => const Color(0xFF9A6A12),
                                    StockLevel.inStock => AppColors.success,
                                  },
                                ),
                              ),
                            ),
                            if (p.demo)
                              Text(
                                tr('демо-данные'),
                                style: AppTextStyles.caption.copyWith(
                                  color: pal.subtext,
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
