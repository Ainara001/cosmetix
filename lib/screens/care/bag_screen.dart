import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/formatters.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/models/care_models.dart';
import 'package:cosmetix/providers/care_provider.dart';
import 'package:cosmetix/providers/catalog_provider.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/common_widgets.dart';
import 'package:cosmetix/widgets/custom_button.dart';
import 'package:cosmetix/services/routine_checks.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';
import 'package:cosmetix/widgets/routine_issues_card.dart';

/// "Моя косметичка": the products the user already has, with dates and a
/// reminder when the package data says the shelf life is ending.
class BagScreen extends StatelessWidget {
  const BagScreen({super.key});

  Future<void> _delete(BuildContext context, MyProduct p) async {
    final ok = await confirmDialog(
      context,
      title: tr('Удалить средство?'),
      message: trf(
        '«{v0}» будет удалено из косметички и из плана ухода. История применения сохранится.',
        {'v0': p.title},
      ),
      confirmLabel: tr('Удалить'),
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await context.read<CareProvider>().deleteProduct(p);
    if (context.mounted) {
      showMessage(context, tr('Средство удалено'), type: MessageType.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final care = context.watch<CareProvider>();
    final pal = context.pal;
    final attention = care.attention;

    return PageScaffold(
      title: tr('Моя косметичка'),
      bigTitle: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          CustomButton(
            label: tr('Добавить средство'),
            icon: Icons.add,
            onPressed: () => Navigator.pushNamed(context, AppRoutes.bagForm),
          ),
          const SizedBox(height: 10),
          CustomButton(
            label: tr('Утренний и вечерний уход'),
            icon: Icons.wb_twilight_outlined,
            outlined: true,
            onPressed: () => Navigator.pushNamed(context, AppRoutes.care),
          ),
          if (attention.isNotEmpty) ...[
            const SizedBox(height: 14),
            AppCard(
              color: context.pal.redSoft,
              borderColor: Colors.transparent,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.notifications_active_outlined,
                    color: AppColors.sale,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      trf('Срок использования на исходе или истёк: {n}', {
                        'n': attention.length,
                      }),
                      style: AppTextStyles.small,
                    ),
                  ),
                ],
              ),
            ),
          ],
          // what in the bag should not meet on the skin / under makeup
          Builder(
            builder: (context) {
              final items = care.bagItems(
                context.watch<CatalogProvider>().byId,
              );
              return RoutineIssuesCard(
                title: tr('Не используйте эти средства вместе'),
                issues: [
                  ...ActiveRules.check(items),
                  ...MakeupCompatibility.checkAll(items),
                ],
              );
            },
          ),
          SectionTitle(tr('Мои средства')),
          if (care.loading && care.bag.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (care.bag.isEmpty)
            EmptyState(
              icon: Icons.shopping_bag_outlined,
              title: tr('Косметичка пуста'),
              subtitle: tr(
                'Добавьте средства, которые у вас уже есть, чтобы составить план ухода и следить за сроками.',
              ),
            ),
          for (final p in care.bag)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                onTap: () => Navigator.pushNamed(
                  context,
                  AppRoutes.bagForm,
                  arguments: p.id,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            p.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodyBold,
                          ),
                        ),
                        PopupMenuButton<String>(
                          tooltip: tr('Действия'),
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.more_vert, size: 18),
                          onSelected: (v) {
                            if (v == 'edit') {
                              Navigator.pushNamed(
                                context,
                                AppRoutes.bagForm,
                                arguments: p.id,
                              );
                            } else {
                              _delete(context, p);
                            }
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text(tr('Редактировать')),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(tr('Удалить')),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (p.category.isNotEmpty)
                      Text(
                        tr(p.category),
                        style: AppTextStyles.caption.copyWith(
                          color: pal.subtext,
                        ),
                      ),
                    const SizedBox(height: 6),
                    _dates(p, pal),
                    const SizedBox(height: 8),
                    ExpiryChip(product: p),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dates(MyProduct p, AppPalette pal) {
    final style = AppTextStyles.small.copyWith(color: pal.subtext);
    final parts = [
      if (p.purchasedAt != null)
        trf('Куплено: {v0}', {'v0': Formatters.date(p.purchasedAt!)}),
      if (p.openedAt != null)
        trf('Вскрыто: {v0}', {'v0': Formatters.date(p.openedAt!)})
      else
        tr('Не вскрыто'),
    ];
    return Text(parts.join('  •  '), style: style);
  }
}

/// Small coloured note about the shelf life ("осталось 40 дней", "срок истёк").
class ExpiryChip extends StatelessWidget {
  const ExpiryChip({super.key, required this.product, this.now});

  final MyProduct product;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final state = product.expiry(now);
    final days = product.daysLeft(now);
    final (text, bg, fg) = switch (state) {
      ExpiryState.unknown => (
        tr(
          'Срок не указан: добавьте дату вскрытия и срок после вскрытия (значок банки на упаковке)',
        ),
        context.pal.field,
        context.pal.subtext,
      ),
      ExpiryState.ok => (
        trf('Использовать до {v0} (осталось {v1} {v2})', {
          'v0': Formatters.date(product.useUntil!),
          'v1': days,
          'v2': Formatters.plural(days!, 'день', 'дня', 'дней'),
        }),
        context.pal.greenSoft,
        AppColors.success,
      ),
      ExpiryState.soon => (
        days == 0
            ? tr('Срок использования заканчивается сегодня')
            : trf('Скоро истекает: осталось {v1} {v2} (до {v0})', {
                'v0': Formatters.date(product.useUntil!),
                'v1': days,
                'v2': Formatters.plural(days!, 'день', 'дня', 'дней'),
              }),
        context.pal.redSoft,
        AppColors.sale,
      ),
      ExpiryState.expired => (
        trf('Срок использования истёк {v0}', {
          'v0': Formatters.date(product.useUntil!),
        }),
        context.pal.redSoft,
        AppColors.sale,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: TextStyle(fontSize: 11.5, color: fg)),
    );
  }
}
