import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/models/cart_models.dart';
import 'package:cosmetix/models/product_filter.dart';
import 'package:cosmetix/providers/cart_provider.dart';
import 'package:cosmetix/providers/settings_provider.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/routes/route_args.dart';
import 'package:cosmetix/widgets/common_widgets.dart';
import 'package:cosmetix/widgets/custom_button.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';
import 'package:cosmetix/widgets/product_card.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  ProductFilter _filter = const ProductFilter();
  ProductSort _sort = ProductSort.newest;
  bool _busy = false;

  Future<void> _openFilters(CartProvider cart) async {
    final picked = await Navigator.pushNamed<Object?>(
      context,
      AppRoutes.filters,
      arguments: FiltersArgs(
        initial: _filter,
        products: [for (final i in cart.items) i.product],
      ),
    );
    if (picked is ProductFilter && mounted) setState(() => _filter = picked);
  }

  Future<void> _clear(CartProvider cart) async {
    if (cart.items.isEmpty) {
      showMessage(context, tr('Корзина уже пуста'), type: MessageType.info);
      return;
    }
    final ok = await confirmDialog(
      context,
      title: tr('Очистить корзину?'),
      message: tr('Все товары будут удалены из корзины.'),
      confirmLabel: tr('Очистить'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    await cart.clear();
    if (mounted) {
      showMessage(context, tr('Корзина очищена'), type: MessageType.success);
    }
  }

  Future<void> _checkout(CartProvider cart) async {
    final fmt = context.read<SettingsProvider>().priceText;
    final ok = await confirmDialog(
      context,
      title: tr('Оформить заказ?'),
      message: cart.bonusToSpend > 0
          ? trf(
              'Товаров: {v0}\nСписано бонусов: −{v3}\nИтого: {v1}\nБонусы за заказ: +{v2}',
              {
                'v0': cart.count,
                'v1': fmt(cart.payable),
                'v2': cart.bonus,
                'v3': cart.bonusToSpend,
              },
            )
          : trf('Товаров: {v0}\nИтого: {v1}\nБонусы за заказ: +{v2}', {
              'v0': cart.count,
              'v1': fmt(cart.payable),
              'v2': cart.bonus,
            }),
      confirmLabel: tr('Оформить'),
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final order = await cart.checkout();
    if (!mounted) return;
    setState(() => _busy = false);
    if (order == null) {
      showMessage(
        context,
        tr('Не удалось оформить заказ. Попробуйте ещё раз'),
        type: MessageType.error,
      );
      return;
    }
    Navigator.pushNamed(context, AppRoutes.orderSuccess, arguments: order);
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final fmt = context.watch<SettingsProvider>().priceText;
    final pal = context.pal;

    final items = cart.items
        .where((i) => _filter.matches(i.product, priceOverride: i.unitPrice))
        .toList();
    switch (_sort) {
      case ProductSort.forYou:
      case ProductSort.newest:
        break;
      case ProductSort.priceAsc:
        items.sort((a, b) => a.unitPrice.compareTo(b.unitPrice));
      case ProductSort.priceDesc:
        items.sort((a, b) => b.unitPrice.compareTo(a.unitPrice));
      case ProductSort.name:
        items.sort((a, b) => a.product.name.compareTo(b.product.name));
    }

    return SafeArea(
      child: Column(
        children: [
          BackTitleBar(
            title: tr('Корзина'),
            bigTitle: true,
            showBack: false,
            trailing: cart.items.isEmpty
                ? null
                : IconButton(
                    tooltip: tr('Очистить корзину'),
                    onPressed: () => _clear(cart),
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AppColors.primaryDark,
                    ),
                  ),
          ),
          // sorting and filters mean nothing for an empty cart
          if (cart.items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
              child: Row(
                children: [
                  Flexible(
                    child: PopupMenuButton<ProductSort>(
                      tooltip: tr('Сортировка'),
                      initialValue: _sort,
                      onSelected: (v) => setState(() => _sort = v),
                      itemBuilder: (_) => [
                        for (final s in ProductSort.cartOptions)
                          PopupMenuItem(value: s, child: Text(tr(s.label))),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.arrow_drop_down, size: 20),
                            Flexible(
                              child: Text(
                                tr(_sort.label),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _openFilters(cart),
                    icon: Badge(
                      isLabelVisible: !_filter.isDefault,
                      smallSize: 8,
                      backgroundColor: AppColors.sale,
                      child: Icon(Icons.filter_alt_outlined, color: pal.text),
                    ),
                    label: Text(
                      tr('Фильтры'),
                      style: TextStyle(color: pal.text),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: cart.loading && cart.items.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : cart.items.isEmpty
                ? EmptyState(
                    icon: Icons.shopping_cart_outlined,
                    title: tr('Корзина пуста'),
                    subtitle: tr(
                      'Добавьте товары из каталога, чтобы оформить заказ',
                    ),
                    actionLabel: tr('Перейти в каталог'),
                    onAction: () => Navigator.pushNamed(
                      context,
                      AppRoutes.catalog,
                      arguments: const CatalogArgs(),
                    ),
                  )
                : items.isEmpty
                ? EmptyState(
                    icon: Icons.filter_alt_off_outlined,
                    title: tr('Ничего не найдено'),
                    subtitle: tr('В корзине нет товаров по выбранным фильтрам'),
                    actionLabel: tr('Сбросить фильтры'),
                    onAction: () =>
                        setState(() => _filter = const ProductFilter()),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    gridDelegate: productGridDelegate(context, extent: 290),
                    itemCount: items.length,
                    itemBuilder: (_, i) => _CartCard(item: items[i]),
                  ),
          ),
          if (cart.items.isNotEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              decoration: BoxDecoration(
                color: pal.surface,
                border: Border(top: BorderSide(color: pal.border)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (cart.spendableBonus > 0)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            trf('Списать бонусы: −{v0}', {
                              'v0': cart.spendableBonus,
                            }),
                            style: AppTextStyles.small,
                          ),
                        ),
                        Switch(
                          value: cart.useBonus,
                          activeThumbColor: AppColors.primaryDark,
                          onChanged: cart.setUseBonus,
                        ),
                      ],
                    ),
                  Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            trf('Итого ({v0})', {'v0': cart.count}),
                            style: AppTextStyles.caption.copyWith(
                              color: pal.subtext,
                            ),
                          ),
                          Text(
                            fmt(cart.payable),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            trf('+{v0} бонусов', {'v0': cart.bonus}),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.primaryDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: CustomButton(
                          label: tr('Оформить заказ'),
                          loading: _busy,
                          onPressed: () => _checkout(cart),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CartCard extends StatelessWidget {
  const _CartCard({required this.item});

  final CartItem item;

  @override
  Widget build(BuildContext context) {
    final cart = context.read<CartProvider>();
    final pal = context.pal;
    return ProductCard(
      product: item.product,
      priceOverride: item.unitPrice,
      onTap: () => Navigator.pushNamed(
        context,
        AppRoutes.product,
        arguments: item.product.id,
      ),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.storeName.isNotEmpty)
            Text(
              tr(item.storeName),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: pal.subtext),
            ),
          Row(
            children: [
              _RoundBtn(
                icon: item.quantity == 1 ? Icons.delete_outline : Icons.remove,
                onTap: () async {
                  if (item.quantity == 1) {
                    final ok = await confirmDialog(
                      context,
                      title: tr('Удалить товар?'),
                      message: trf('«{v0}» будет удалён из корзины.', {
                        'v0': tr(item.product.name),
                      }),
                      confirmLabel: tr('Удалить'),
                      destructive: true,
                    );
                    if (!ok) return;
                  }
                  await cart.setQuantity(item, item.quantity - 1);
                },
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${item.quantity}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              _RoundBtn(
                icon: Icons.add,
                onTap: () {
                  if (item.quantity >= 10) {
                    showMessage(
                      context,
                      tr('Максимум 10 штук одного товара'),
                      type: MessageType.warning,
                    );
                    return;
                  }
                  cart.setQuantity(item, item.quantity + 1);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    customBorder: const CircleBorder(),
    child: Container(
      width: 28,
      height: 28,
      decoration: const BoxDecoration(
        color: AppColors.primarySoft,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 16, color: AppColors.primaryDark),
    ),
  );
}
