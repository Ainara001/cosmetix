import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/models/cart_models.dart';
import 'package:cosmetix/providers/auth_provider.dart';
import 'package:cosmetix/providers/nav_provider.dart';
import 'package:cosmetix/providers/settings_provider.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/custom_button.dart';

/// Added screen: order confirmation.
class OrderSuccessScreen extends StatefulWidget {
  const OrderSuccessScreen({super.key, required this.order});

  final Order order;

  @override
  State<OrderSuccessScreen> createState() => _OrderSuccessScreenState();
}

class _OrderSuccessScreenState extends State<OrderSuccessScreen> {
  @override
  void initState() {
    super.initState();
    // bonus points were added in SQLite: refresh the profile counters
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AuthProvider>().reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    final fmt = context.watch<SettingsProvider>().priceText;
    final pal = context.pal;
    final order = widget.order;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _home(context);
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Spacer(),
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: context.pal.greenSoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 56,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  trf('Заказ №{v0} оформлен', {'v0': order.id}),
                  style: AppTextStyles.h2,
                ),
                const SizedBox(height: 6),
                Text(
                  tr(
                    'Спасибо за покупку! Оплата и доставка в приложении имитируются.',
                  ),
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body.copyWith(color: pal.subtext),
                ),
                const SizedBox(height: 20),
                AppCard(
                  child: Column(
                    children: [
                      for (final l in order.lines)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${tr(l.name)} × ${l.quantity}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.small,
                                ),
                              ),
                              Text(
                                fmt(l.price * l.quantity),
                                style: AppTextStyles.bodyBold,
                              ),
                            ],
                          ),
                        ),
                      const Divider(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              tr('Итого'),
                              style: AppTextStyles.bodyBold,
                            ),
                          ),
                          Text(
                            fmt(order.total),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      if (order.bonusSpent > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(child: Text(tr('Списано бонусов'))),
                            Text(
                              '−${order.bonusSpent}',
                              style: TextStyle(
                                color: context.pal.accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(child: Text(tr('Начислено бонусов'))),
                          Text(
                            '+${order.bonus}',
                            style: TextStyle(
                              color: context.pal.accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                CustomButton(
                  label: tr('Мои покупки'),
                  onPressed: () {
                    context.read<NavProvider>().setTab(NavProvider.profile);
                    Navigator.of(context).popUntil((r) => r.isFirst);
                    Navigator.pushNamed(context, AppRoutes.orders);
                  },
                ),
                const SizedBox(height: 10),
                CustomButton(
                  label: tr('На главную'),
                  outlined: true,
                  onPressed: () => _home(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _home(BuildContext context) {
    context.read<NavProvider>().setTab(NavProvider.home);
    Navigator.of(context).popUntil((r) => r.isFirst);
  }
}
