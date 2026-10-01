import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/formatters.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/models/safety_models.dart';
import 'package:cosmetix/providers/cart_provider.dart';
import 'package:cosmetix/providers/catalog_provider.dart';
import 'package:cosmetix/providers/reviews_provider.dart';
import 'package:cosmetix/providers/safety_provider.dart';
import 'package:cosmetix/providers/settings_provider.dart';
import 'package:cosmetix/repositories/review_repository.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/common_widgets.dart';
import 'package:cosmetix/widgets/custom_button.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';
import 'package:cosmetix/widgets/product_art.dart';

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
      '«${product.name}» добавлен в корзину',
      type: MessageType.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final product = context.watch<CatalogProvider>().byId(widget.productId);
    final pal = context.pal;
    final fmt = context.watch<SettingsProvider>().priceText;

    if (product == null) {
      return PageScaffold(
        title: 'О товаре',
        child: const EmptyState(
          icon: Icons.search_off,
          title: 'Товар не найден',
          subtitle: 'Возможно, он был удалён из каталога',
        ),
      );
    }

    final reviews = context.watch<ReviewsProvider>();
    final available = _prices.where((p) => p.inStock).length;
    final selected = _selected;
    final price = selected?.price ?? product.price;

    return PageScaffold(
      title: 'О товаре',
      trailing: IconButton(
        tooltip: product.isFavorite ? 'Убрать из избранного' : 'В избранное',
        onPressed: () async {
          final state = await context.read<CatalogProvider>().toggleFavorite(
            product.id,
          );
          if (state != null && context.mounted) {
            showMessage(
              context,
              state ? 'Добавлено в избранное' : 'Удалено из избранного',
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
                                    ? 'В НАЛИЧИИ'
                                    : 'НЕТ В НАЛИЧИИ',
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
                      Text(product.name, style: AppTextStyles.h2),
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
                              product.inStock ? 'В наличии' : 'Нет в наличии',
                              style: TextStyle(
                                fontSize: 11,
                                color: product.inStock
                                    ? AppColors.success
                                    : pal.subtext,
                              ),
                            ),
                          ),
                          Text(
                            'Доступна в $available '
                            '${Formatters.plural(available, 'магазине', 'магазинах', 'магазинах')}',
                            style: AppTextStyles.small.copyWith(
                              color: pal.subtext,
                            ),
                          ),
                        ],
                      ),
                      if (product.description.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(product.description, style: AppTextStyles.body),
                      ],
                      SectionTitle(
                        'Сравнение цен в магазинах',
                        trailing: LinkText(
                          'Все цены',
                          onTap: () => Navigator.pushNamed(
                            context,
                            AppRoutes.priceCompare,
                            arguments: product.id,
                          ),
                        ),
                      ),
                      for (var i = 0; i < _prices.length; i++)
                        _StoreRow(
                          index: i + 1,
                          price: _prices[i],
                          selected: _prices[i].storeId == _storeId,
                          onTap: () {
                            if (!_prices[i].inStock) {
                              showMessage(
                                context,
                                'В магазине «${_prices[i].storeName}» товара нет в наличии',
                                type: MessageType.warning,
                              );
                              return;
                            }
                            setState(() => _storeId = _prices[i].storeId);
                          },
                        ),
                      const SectionTitle('Анализ состава'),
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
                                          ? 'Безопасный состав'
                                          : 'Состав требует внимания',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: _analysis!.scoreColor,
                                      ),
                                    ),
                                    Text(
                                      '${product.naturalPercent}% натуральных и '
                                      'немедикаментозных компонентов.',
                                      style: AppTextStyles.caption.copyWith(
                                        color: pal.subtext,
                                      ),
                                    ),
                                    if (_analysis!.blacklistHits.isNotEmpty)
                                      Text(
                                        'Из вашего чёрного списка: '
                                        '${_analysis!.blacklistHits.join(', ')}',
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
                      SectionTitle(
                        'Отзывы${reviews.reviews.isEmpty ? '' : ' (${reviews.reviews.length})'}',
                        trailing: LinkText(
                          'Все отзывы',
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
                          'Отзывов пока нет. Станьте первым!',
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
                            'Цена',
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
                              ? 'Ещё одну в корзину'
                              : 'В корзину',
                          icon: Icons.shopping_cart_outlined,
                          onPressed: product.inStock
                              ? () => _addToCart(product)
                              : null,
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
  });

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
                  Text(price.storeName, style: AppTextStyles.bodyBold),
                  Text(
                    '${price.distanceM >= 1000 ? '${(price.distanceM / 1000).toStringAsFixed(1)} км' : '${price.distanceM} м'} от вас',
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
                    color: index == 1 && price.inStock
                        ? AppColors.sale
                        : pal.text,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: price.inStock ? AppColors.successSoft : pal.field,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    price.inStock ? 'В наличии' : 'Нет',
                    style: TextStyle(
                      fontSize: 9,
                      color: price.inStock ? AppColors.success : pal.subtext,
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
