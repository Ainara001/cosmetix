import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/formatters.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/models/cart_models.dart';
import 'package:cosmetix/providers/cart_provider.dart';
import 'package:cosmetix/providers/settings_provider.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/routes/route_args.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/common_widgets.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';
import 'package:cosmetix/widgets/product_art.dart';

/// Added screen: "Покупки" (purchase history).
class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  Future<void> _delete(BuildContext context, Order o) async {
    final ok = await confirmDialog(
      context,
      title: 'Удалить заказ №${o.id}?',
      message: 'Запись о покупке будет удалена из истории.',
      confirmLabel: 'Удалить',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await context.read<CartProvider>().deleteOrder(o);
    if (context.mounted) {
      showMessage(context, 'Заказ удалён', type: MessageType.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final fmt = context.watch<SettingsProvider>().priceText;
    final pal = context.pal;

    return PageScaffold(
      title: 'Покупки',
      bigTitle: true,
      child: cart.orders.isEmpty
          ? EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Покупок пока нет',
              subtitle: 'Оформленные заказы появятся здесь',
              actionLabel: 'Перейти в каталог',
              onAction: () => Navigator.pushNamed(
                context,
                AppRoutes.catalog,
                arguments: const CatalogArgs(),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: cart.orders.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final o = cart.orders[i];
                return AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Заказ №${o.id} • ${Formatters.date(o.createdAt)}',
                              style: AppTextStyles.bodyBold,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Удалить',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _delete(context, o),
                            icon: const Icon(Icons.delete_outline, size: 20),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.successSoft,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          o.status,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.success,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final l in o.lines)
                        InkWell(
                          onTap: () => Navigator.pushNamed(
                            context,
                            AppRoutes.product,
                            arguments: l.productId,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 44,
                                  height: 36,
                                  child: ProductArt(
                                    art: l.art,
                                    color: l.color,
                                    radius: 8,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '${l.name} × ${l.quantity}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.small,
                                  ),
                                ),
                                Text(
                                  fmt(l.price * l.quantity),
                                  style: AppTextStyles.small,
                                ),
                              ],
                            ),
                          ),
                        ),
                      const Divider(height: 18),
                      Row(
                        children: [
                          Text(
                            '+${o.bonus} бонусов',
                            style: TextStyle(fontSize: 12, color: pal.subtext),
                          ),
                          const Spacer(),
                          Text(
                            fmt(o.total),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
