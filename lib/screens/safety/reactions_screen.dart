import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/formatters.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/models/safety_models.dart';
import 'package:cosmetix/providers/safety_provider.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/common_widgets.dart';
import 'package:cosmetix/widgets/custom_button.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';
import 'package:cosmetix/widgets/product_art.dart';

class ReactionsScreen extends StatelessWidget {
  const ReactionsScreen({super.key});

  Future<void> _delete(BuildContext context, Reaction r) async {
    final ok = await confirmDialog(
      context,
      title: tr('Удалить запись?'),
      message: trf('Реакция на «{v0}» будет удалена из дневника.', {
        'v0': tr(r.productName),
      }),
      confirmLabel: tr('Удалить'),
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await context.read<SafetyProvider>().deleteReaction(r);
    if (context.mounted) {
      showMessage(context, tr('Запись удалена'), type: MessageType.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final safety = context.watch<SafetyProvider>();
    final pal = context.pal;

    return PageScaffold(
      title: tr('Дневник реакций'),
      bigTitle: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          CustomButton(
            label: tr('Добавить реакцию'),
            icon: Icons.add,
            onPressed: () =>
                Navigator.pushNamed(context, AppRoutes.reactionForm),
          ),
          SectionTitle(tr('История кожных реакций')),
          if (safety.reactions.isEmpty)
            EmptyState(
              icon: Icons.healing_outlined,
              title: tr('Реакций не было'),
              subtitle: tr(
                'Записывайте реакции кожи на косметику, чтобы избегать неподходящих средств',
              ),
            ),
          for (final r in safety.reactions)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                onTap: () => Navigator.pushNamed(
                  context,
                  AppRoutes.reactionForm,
                  arguments: r.id,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            Formatters.date(r.date),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.small.copyWith(
                              color: pal.subtext,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          tr('Тяжесть: '),
                          style: AppTextStyles.small.copyWith(
                            color: pal.subtext,
                          ),
                        ),
                        for (var i = 1; i <= 5; i++)
                          Padding(
                            padding: const EdgeInsets.only(left: 2),
                            child: Icon(
                              Icons.circle,
                              size: 8,
                              color: i <= r.severity
                                  ? AppColors.sale
                                  : pal.border,
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
                                AppRoutes.reactionForm,
                                arguments: r.id,
                              );
                            } else {
                              _delete(context, r);
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
                    const Divider(height: 10),
                    Row(
                      children: [
                        SizedBox(
                          width: 44,
                          height: 36,
                          child: ProductArt(
                            art: r.art,
                            color: r.color,
                            radius: 8,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr(r.productName),
                                style: AppTextStyles.bodyBold,
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.saleSoft,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  tr(r.title),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.sale,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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
