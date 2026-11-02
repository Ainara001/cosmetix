import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/formatters.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/models/safety_models.dart';
import 'package:cosmetix/providers/cart_provider.dart';
import 'package:cosmetix/providers/chat_provider.dart';
import 'package:cosmetix/providers/nav_provider.dart';
import 'package:cosmetix/providers/catalog_provider.dart';
import 'package:cosmetix/providers/location_provider.dart';
import 'package:cosmetix/providers/reviews_provider.dart';
import 'package:cosmetix/providers/safety_provider.dart';
import 'package:cosmetix/providers/settings_provider.dart';
import 'package:cosmetix/repositories/review_repository.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/routes/route_args.dart';
import 'package:cosmetix/services/ingredient_catalog.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/common_widgets.dart';
import 'package:cosmetix/widgets/custom_button.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';
import 'package:cosmetix/widgets/product_art.dart';
import 'package:cosmetix/widgets/why_it_suits_card.dart';

class ProductScreen extends StatelessWidget {
  const ProductScreen({super.key, required this.productId});

  final int productId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (c) =>
          ReviewsProvider(c.read<ReviewRepository>(), productId)..load(),
      child: _ProductBody(productId: productId),
    );
  }
}

class _ProductBody extends StatefulWidget {
  const _ProductBody({required this.productId});

  final int productId;

  @override
  State<_ProductBody> createState() => _ProductBodyState();
}

class _ProductBodyState extends State<_ProductBody> {
  List<StorePrice> _prices = [];
  IngredientAnalysis? _analysis;
  int? _storeId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final catalog = context.read<CatalogProvider>();
    final safety = context.read<SafetyProvider>();
    try {
      final prices = await catalog.storePrices(widget.productId);
      final analysis = await safety.analyze(widget.productId);
      if (!mounted) return;
      setState(() {
        _prices = prices;
        _analysis = analysis;
        final available = prices.where((p) => p.inStock).toList();
        _storeId = available.isEmpty ? null : available.first.storeId;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  StorePrice? get _selected {
    for (final p in _prices) {
      if (p.storeId == _storeId) return p;
    }
    return null;
  }

  /// Opens the chat and asks about this product (the assistant gets the
  /// product facts together with the user's Beauty Profile).
  void _askAi(Product product) {
    final chat = context.read<ChatProvider>();
    Navigator.of(context).popUntil((r) => r.isFirst);
    context.read<NavProvider>().setTab(NavProvider.chat);
    chat.send(tr('Подойдёт ли мне этот товар?'), productId: product.id);
  }

  Future<void> _addToCart(Product product) async {
    final error = await context.read<CartProvider>().add(
      product,
      storeId: _storeId,
    );
    if (!mounted) return;
    if (error != null) {
      showMessage(context, error, type: MessageType.warning);
      return;
    }
    showMessage(
      context,
      trf('«{v0}» добавлен в корзину', {'v0': tr(product.name)}),
      type: MessageType.success,
    );
  }

  /// Acids and actives found in the INCI list; a tap shows every product
  /// with the same ingredient.
  List<Widget> _activeChips(BuildContext context, Product product) {
    final actives = IngredientCatalog.activesOf(product);
    if (actives.isEmpty) return const [];
    return [
      Text(
        tr('Ключевые компоненты'),
        style: AppTextStyles.caption.copyWith(color: context.pal.subtext),
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final g in actives)
            ActionChip(
              visualDensity: VisualDensity.compact,
              label: Text(tr(g.label), style: const TextStyle(fontSize: 12)),
              backgroundColor: AppColors.primarySoft,
              side: BorderSide.none,
              onPressed: () => Navigator.pushNamed(
                context,
                AppRoutes.catalog,
                arguments: CatalogArgs(ingredients: {g.code}),
              ),
            ),
        ],
      ),
      const SizedBox(height: 10),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final product = context.watch<CatalogProvider>().byId(widget.productId);
    final pal = context.pal;
    final fmt = context.watch<SettingsProvider>().priceText;
    final loc = context.watch<LocationProvider>();
    // distances from the user's position (or the city centre)
    // nearest first, shops that have it before shops that do not
    final prices =
        [
          for (final p in _prices)
            p.hasPosition ? p.withDistance(loc.distanceTo(p.lat!, p.lng!)) : p,
        ]..sort((a, b) {
          if (a.inStock != b.inStock) return a.inStock ? -1 : 1;
          return a.distanceM.compareTo(b.distanceM);
        });

    if (product == null) {
      return PageScaffold(
        title: tr('О товаре'),
        child: EmptyState(
          icon: Icons.search_off,
          title: tr('Товар не найден'),
          subtitle: tr('Возможно, он был удалён из каталога'),
        ),
      );
    }

    final reviews = context.watch<ReviewsProvider>();
    final available = prices.where((p) => p.inStock).length;
    final best = prices
        .where((p) => p.inStock)
        .fold<int?>(null, (m, p) => m == null || p.price < m ? p.price : m);
    final selected = _selected;
    final price = selected?.price ?? product.price;

    return PageScaffold(
      title: tr('О товаре'),
      // the price/cart bar sits at the bottom: no second bar under it
      showNav: false,
      trailing: IconButton(
        tooltip: product.isFavorite
            ? tr('Убрать из избранного')
            : tr('В избранное'),
        onPressed: () async {
          final state = await context.read<CatalogProvider>().toggleFavorite(
            product.id,
          );
          if (state != null && context.mounted) {
            showMessage(
              context,
              state ? tr('Добавлено в избранное') : tr('Удалено из избранного'),
              type: state ? MessageType.success : MessageType.info,
            );
          }
        },
        icon: Icon(
          product.isFavorite ? Icons.favorite : Icons.favorite_border,
          color: AppColors.primaryDark,
        ),
      ),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      SizedBox(
                        height: 220,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ProductArt(
                                art: product.art,
                                color: product.color,
                                radius: 20,
                              ),
                            ),
                            Positioned(
                              left: 10,
                              top: 10,
                              child: _Badge(
                                text: product.inStock
                                    ? tr('В НАЛИЧИИ')
                                    : tr('НЕТ В НАЛИЧИИ'),
                                color: product.inStock
                                    ? AppColors.success
                                    : const Color(0xFF8E8689),
                              ),
                            ),
                            if (product.hasDiscount)
                              Positioned(
                                right: 10,
                                top: 10,
                                child: _Badge(
                                  text: '-${product.discountPercent}%',
                                  color: AppColors.sale,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        product.brand,
                        style: AppTextStyles.small.copyWith(color: pal.subtext),
                      ),
                      Text(tr(product.name), style: AppTextStyles.h2),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: product.inStock
                                  ? AppColors.successSoft
                                  : pal.field,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              product.inStock
                                  ? tr('В наличии')
                                  : tr('Нет в наличии'),
                              style: TextStyle(
                                fontSize: 11,
                                color: product.inStock
                                    ? AppColors.success
                                    : pal.subtext,
                              ),
                            ),
                          ),
                          Text(
                            trf('Доступна в {available} {v0}', {
                              'available': available,
                              'v0': Formatters.plural(
                                available,
                                'магазине',
                                'магазинах',
                                'магазинах',
                              ),
                            }),
                            style: AppTextStyles.small.copyWith(
                              color: pal.subtext,
                            ),
                          ),
                        ],
                      ),
                      if (product.description.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          tr(product.description),
                          style: AppTextStyles.body,
                        ),
                      ],
                      WhyItSuitsCard(productId: product.id),
                      const SizedBox(height: 10),
                      CustomButton(
                        label: tr('Спросить ИИ: подойдёт ли мне?'),
                        icon: Icons.smart_toy_outlined,
                        outlined: true,
                        onPressed: () => _askAi(product),
                      ),
                      SectionTitle(
                        tr('Сравнение цен в магазинах'),
                        trailing: LinkText(
                          tr('Все цены'),
                          onTap: () => Navigator.pushNamed(
                            context,
                            AppRoutes.priceCompare,
                            arguments: product.id,
                          ),
                        ),
                      ),
                      for (var i = 0; i < prices.length && i < 4; i++)
                        _StoreRow(
                          index: i + 1,
                          price: prices[i],
                          isBest: prices[i].inStock && prices[i].price == best,
                          selected: prices[i].storeId == _storeId,
                          onTap: () {
                            if (!prices[i].inStock) {
                              showMessage(
                                context,
                                trf('В магазине «{v0}» товара нет в наличии', {
                                  'v0': tr(prices[i].storeName),
                                }),
                                type: MessageType.warning,
                              );
                              return;
                            }
                            setState(() => _storeId = prices[i].storeId);
                          },
                        ),
                      if (prices.length > 4)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            trf('и ещё {v0} магазинов', {
                              'v0': prices.length - 4,
                            }),
                            style: AppTextStyles.caption.copyWith(
                              color: pal.subtext,
                            ),
                          ),
                        ),
                      CustomButton(
                        label: tr('Где купить рядом: карта'),
                        icon: Icons.map_outlined,
                        outlined: true,
                        onPressed: () => Navigator.pushNamed(
                          context,
                          AppRoutes.stores,
                          arguments: StoresArgs(productId: product.id),
                        ),
                      ),
                      SectionTitle(tr('Анализ состава')),
                      if (_analysis != null)
                        AppCard(
                          onTap: () => Navigator.pushNamed(
                            context,
                            AppRoutes.analysis,
                            arguments: product.id,
                          ),
                          color: _analysis!.score >= 7.5
                              ? AppColors.successSoft
                              : AppColors.saleSoft,
                          borderColor: Colors.transparent,
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: _analysis!.scoreColor,
                                child: Text(
                                  _analysis!.grade,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _analysis!.score >= 7.5
                                          ? tr('Безопасный состав')
                                          : tr('Состав требует внимания'),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: _analysis!.scoreColor,
                                      ),
                                    ),
                                    Text(
                                      trf(
                                        '{v0}% натуральных и немедикаментозных компонентов.',
                                        {'v0': product.naturalPercent},
                                      ),
                                      style: AppTextStyles.caption.copyWith(
                                        color: pal.subtext,
                                      ),
                                    ),
                                    if (_analysis!.blacklistHits.isNotEmpty)
                                      Text(
                                        trf('Из вашего чёрного списка: {v0}', {
                                          'v0': _analysis!.blacklistHits
                                              .map(tr)
                                              .join(', '),
                                        }),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.sale,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                      if (product.inci.isNotEmpty) ...[
                        SectionTitle(tr('Полный состав (INCI)')),
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ..._activeChips(context, product),
                              SelectableText(
                                product.inci,
                                style: AppTextStyles.small,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                trf('Источник: {v0}', {
                                  'v0':
                                      Uri.tryParse(product.sourceUrl)?.host ??
                                      product.sourceUrl,
                                }),
                                style: AppTextStyles.caption.copyWith(
                                  color: pal.subtext,
                                ),
                              ),
                              Text(
                                tr(
                                  'Состав может отличаться по оттенкам и сериям: сверяйтесь с упаковкой.',
                                ),
                                style: AppTextStyles.caption.copyWith(
                                  color: pal.subtext,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      SectionTitle(
                        trf('Отзывы{v0}', {
                          'v0': reviews.reviews.isEmpty
                              ? ''
                              : ' (${reviews.reviews.length})',
                        }),
                        trailing: LinkText(
                          tr('Все отзывы'),
                          onTap: () async {
                            await Navigator.pushNamed(
                              context,
                              AppRoutes.reviews,
                              arguments: product.id,
                            );
                            if (context.mounted) {
                              context.read<ReviewsProvider>().load();
                            }
                          },
                        ),
                      ),
                      if (reviews.reviews.isEmpty)
                        Text(
                          tr('Отзывов пока нет. Станьте первым!'),
                          style: TextStyle(color: pal.subtext),
                        )
                      else
                        for (final r in reviews.reviews.take(2))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: AppCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        r.author,
                                        style: AppTextStyles.bodyBold,
                                      ),
                                      const Spacer(),
                                      Text(
                                        Formatters.ago(r.createdAt),
                                        style: AppTextStyles.caption.copyWith(
                                          color: pal.subtext,
                                        ),
                                      ),
                                    ],
                                  ),
                                  StarRow(value: r.rating, size: 14),
                                  const SizedBox(height: 4),
                                  Text(r.body, style: AppTextStyles.small),
                                ],
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  decoration: BoxDecoration(
                    color: pal.surface,
                    border: Border(top: BorderSide(color: pal.border)),
                  ),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            tr('Цена'),
                            style: AppTextStyles.caption.copyWith(
                              color: pal.subtext,
                            ),
                          ),
                          Text(
                            fmt(price),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.sale,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: CustomButton(
                          label:
                              context.watch<CartProvider>().contains(product.id)
                              ? tr('Ещё одну в корзину')
                              : tr('В корзину'),
                          icon: Icons.shopping_cart_outlined,
                          onPressed: () => _addToCart(product),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _StoreRow extends StatelessWidget {
  const _StoreRow({
    required this.index,
    required this.price,
    required this.selected,
    required this.onTap,
    this.isBest = false,
  });

  /// The lowest price among the shops that have the product.
  final bool isBest;
  final int index;
  final StorePrice price;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final fmt = context.watch<SettingsProvider>().priceText;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(10),
        borderColor: selected ? AppColors.primaryDark : null,
        child: Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: AppColors.primarySoft,
              child: Text(
                '0$index',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(price.storeName), style: AppTextStyles.bodyBold),
                  Text(
                    tr(price.address),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption.copyWith(color: pal.subtext),
                  ),
                  Text(
                    trf('{v0} от вас', {
                      'v0': price.distanceM >= 1000
                          ? trf('{v0} км', {
                              'v0': (price.distanceM / 1000).toStringAsFixed(1),
                            })
                          : trf('{v0} м', {'v0': price.distanceM}),
                    }),
                    style: AppTextStyles.caption.copyWith(color: pal.subtext),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  fmt(price.price),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: isBest && price.inStock ? AppColors.sale : pal.text,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: switch (price.level) {
                      StockLevel.inStock => AppColors.successSoft,
                      StockLevel.low => const Color(0xFFFBF0D9),
                      StockLevel.out => pal.field,
                    },
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    switch (price.level) {
                      StockLevel.inStock => tr('В наличии'),
                      StockLevel.low => tr('Мало'),
                      StockLevel.out => tr('Нет'),
                    },
                    style: TextStyle(
                      fontSize: 9,
                      color: switch (price.level) {
                        StockLevel.inStock => AppColors.success,
                        StockLevel.low => const Color(0xFF9A6A12),
                        StockLevel.out => pal.subtext,
                      },
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
