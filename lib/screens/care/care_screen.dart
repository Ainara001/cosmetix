import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
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

/// "Мой уход": the user's own morning and evening plan, built from the
/// cosmetic bag, with a mark for every product used today.
class CareScreen extends StatefulWidget {
  const CareScreen({super.key});

  @override
  State<CareScreen> createState() => _CareScreenState();
}

class _CareScreenState extends State<CareScreen> {
  CarePeriod _period = DateTime.now().hour >= 16
      ? CarePeriod.evening
      : CarePeriod.morning;

  Future<void> _add(CareProvider care) async {
    final free = [
      for (final p in care.bag)
        if (!care.inPlan(_period, p.id)) p,
    ];
    if (care.bag.isEmpty) {
      final go = await confirmDialog(
        context,
        title: tr('Косметичка пуста'),
        message: tr('Сначала добавьте средства в «Мою косметичку».'),
        confirmLabel: tr('Добавить средство'),
      );
      if (go && mounted) Navigator.pushNamed(context, AppRoutes.bagForm);
      return;
    }
    if (free.isEmpty) {
      showMessage(
        context,
        tr('Все ваши средства уже в этом плане'),
        type: MessageType.info,
      );
      return;
    }
    final picked = await showModalBottomSheet<MyProduct>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                tr('Выберите средство из косметички'),
                style: AppTextStyles.subtitle,
              ),
            ),
            for (final p in free)
              ListTile(
                title: Text(p.title),
                subtitle: p.category.isEmpty ? null : Text(tr(p.category)),
                onTap: () => Navigator.pop(ctx, p),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    // a new conflict with what is already in this plan: say it before adding
    final catalog = context.read<CatalogProvider>();
    final before = {
      for (final i in care.planIssues(_period, catalog.byId)) i.text,
    };
    final fresh = [
      for (final i in care.planIssues(
        _period,
        catalog.byId,
        extra: RoutineItem.fromBag(
          picked,
          picked.productId == null ? null : catalog.byId(picked.productId!),
        ),
      ))
        if (!before.contains(i.text)) i,
    ];
    if (fresh.isNotEmpty) {
      final ok = await confirmDialog(
        context,
        title: tr('Возможный конфликт'),
        message:
            '${fresh.map((i) => i.text).join('\n\n')}\n\n${tr('Добавить в план всё равно?')}',
        confirmLabel: tr('Добавить'),
      );
      if (!ok || !mounted) return;
    }
    final error = await care.addStep(_period, picked);
    if (error != null && mounted) {
      showMessage(context, error, type: MessageType.warning);
    }
  }

  @override
  Widget build(BuildContext context) {
    final care = context.watch<CareProvider>();
    final pal = context.pal;
    final steps = care.steps(_period);
    final done = care.doneCount(_period);

    return PageScaffold(
      title: tr('Мой уход'),
      bigTitle: true,
      trailing: IconButton(
        tooltip: tr('История ухода'),
        icon: Icon(Icons.history, color: context.pal.accent),
        onPressed: () => Navigator.pushNamed(context, AppRoutes.careHistory),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Row(
            children: [
              AppChip(
                label: tr('Утро'),
                selected: _period == CarePeriod.morning,
                onTap: () => setState(() => _period = CarePeriod.morning),
              ),
              const SizedBox(width: 8),
              AppChip(
                label: tr('Вечер'),
                selected: _period == CarePeriod.evening,
                onTap: () => setState(() => _period = CarePeriod.evening),
              ),
            ],
          ),
          const SizedBox(height: 12),
          CustomButton(
            label: tr('Подбор ухода'),
            icon: Icons.spa_outlined,
            outlined: true,
            onPressed: () =>
                Navigator.pushNamed(context, AppRoutes.careSelection),
          ),
          const SizedBox(height: 16),
          Text(
            _period == CarePeriod.morning
                ? tr('Утренний уход')
                : tr('Вечерний уход'),
            style: AppTextStyles.subtitle,
          ),
          if (steps.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                trf('Сегодня отмечено: {v0} из {v1}', {
                  'v0': done,
                  'v1': steps.length,
                }),
                style: AppTextStyles.small.copyWith(color: pal.subtext),
              ),
            ),
          RoutineIssuesCard(
            issues: care.planIssues(
              _period,
              context.watch<CatalogProvider>().byId,
            ),
            padding: const EdgeInsets.only(bottom: 10),
          ),
          const SizedBox(height: 10),
          if (care.loading && steps.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (steps.isEmpty)
            EmptyState(
              icon: Icons.spa_outlined,
              title: tr('План пока пуст'),
              subtitle: tr(
                'Добавьте средства из косметички в том порядке, в котором вы ими пользуетесь.',
              ),
            ),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _StepTile(
                step: steps[i],
                index: i,
                last: i == steps.length - 1,
                used: care.isUsedToday(_period, steps[i].product.id),
              ),
            ),
          const SizedBox(height: 6),
          CustomButton(
            label: tr('Добавить средство в план'),
            icon: Icons.add,
            onPressed: () => _add(care),
          ),
          const SizedBox(height: 10),
          CustomButton(
            label: tr('Моя косметичка'),
            outlined: true,
            onPressed: () => Navigator.pushNamed(context, AppRoutes.bag),
          ),
          const SizedBox(height: 14),
          Text(
            tr(
              'Это ваш личный план, а не медицинская рекомендация. Схема не обязана быть одинаковой для всех: ориентируйтесь на состояние кожи. При раздражении прекратите использование и обратитесь к специалисту.',
            ),
            style: AppTextStyles.caption.copyWith(color: pal.subtext),
          ),
        ],
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.step,
    required this.index,
    required this.last,
    required this.used,
  });

  final CareStep step;
  final int index;
  final bool last;
  final bool used;

  @override
  Widget build(BuildContext context) {
    final care = context.read<CareProvider>();
    final pal = context.pal;
    final expired = step.product.expiry() == ExpiryState.expired;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      child: Row(
        children: [
          Checkbox(
            value: used,
            activeColor: AppColors.primaryDark,
            onChanged: (v) => care.setUsed(step, v ?? false),
          ),
          Expanded(
            child: InkWell(
              onTap: () => care.setUsed(step, !used),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${index + 1}. ${step.product.title}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyBold.copyWith(
                      decoration: used ? TextDecoration.lineThrough : null,
                      color: used ? pal.subtext : null,
                    ),
                  ),
                  if (expired)
                    Text(
                      tr('Срок использования истёк'),
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.sale,
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: tr('Выше'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.keyboard_arrow_up),
            onPressed: index == 0 ? null : () => care.move(step, -1),
          ),
          IconButton(
            tooltip: tr('Ниже'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: last ? null : () => care.move(step, 1),
          ),
          IconButton(
            tooltip: tr('Убрать из плана'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => care.removeStep(step),
          ),
        ],
      ),
    );
  }
}
