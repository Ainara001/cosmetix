import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/formatters.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/models/reaction_insights.dart';
import 'package:cosmetix/models/safety_models.dart';
import 'package:cosmetix/providers/safety_provider.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/common_widgets.dart';
import 'package:cosmetix/widgets/custom_button.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';
import 'package:cosmetix/widgets/product_art.dart';

class ReactionsScreen extends StatefulWidget {
  const ReactionsScreen({super.key});

  @override
  State<ReactionsScreen> createState() => _ReactionsScreenState();
}

class _ReactionsScreenState extends State<ReactionsScreen> {
  ReactionInsights _insights = const ReactionInsights.empty();
  int _insightsFor = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInsights());
  }

  Future<void> _loadInsights() async {
    final safety = context.read<SafetyProvider>();
    final key = Object.hash(
      safety.reactions.length,
      safety.reactions.fold<int>(0, (s, r) => s + r.severity + r.productId),
    );
    if (key == _insightsFor) return;
    _insightsFor = key;
    final insights = await safety.insights();
    if (mounted) setState(() => _insights = insights);
  }

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInsights());

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
          if (!_insights.isEmpty) _InsightsCard(insights: _insights),
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
                                  color: context.pal.redSoft,
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

/// "Повторяющиеся наблюдения": what repeats in the user's own records.
class _InsightsCard extends StatelessWidget {
  const _InsightsCard({required this.insights});

  final ReactionInsights insights;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: AppCard(
        color: context.pal.pinkSoft,
        borderColor: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.insights_outlined,
                  size: 18,
                  color: context.pal.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('Повторяющиеся наблюдения'),
                    style: AppTextStyles.subtitle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final p in insights.repeatedProducts)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  trf(
                    'Средство «{v0}» встречается в дневнике {v1} {v2} ({v3} — {v4}), средняя тяжесть {v5} из 5.',
                    {
                      'v0': tr(p.productName),
                      'v1': p.count,
                      'v2': Formatters.plural(p.count, 'раз', 'раза', 'раз'),
                      'v3': Formatters.date(p.firstDate),
                      'v4': Formatters.date(p.lastDate),
                      'v5': p.averageSeverity.toStringAsFixed(1),
                    },
                  ),
                  style: AppTextStyles.small,
                ),
              ),
            for (final i in insights.sharedIngredients)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  trf(
                    'Компонент «{v0}» есть в составе {v1} из {v2} средств с записями.',
                    {
                      'v0': tr(i.name),
                      'v1': i.productCount,
                      'v2': i.totalProducts,
                    },
                  ),
                  style: AppTextStyles.small,
                ),
              ),
            const SizedBox(height: 4),
            Text(
              tr(
                'Это наблюдения по вашим записям, а не вывод о причине: совпадение по времени или по составу не доказывает, что реакцию вызвало именно это средство. При сильной или затяжной реакции обратитесь к врачу.',
              ),
              style: AppTextStyles.caption.copyWith(color: pal.subtext),
            ),
          ],
        ),
      ),
    );
  }
}
