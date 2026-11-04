import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/models/recommendation.dart';
import 'package:cosmetix/providers/catalog_provider.dart';
import 'package:cosmetix/widgets/app_card.dart';

/// "Why it suits you" block on the product page (only with a Beauty Profile).
class WhyItSuitsCard extends StatelessWidget {
  const WhyItSuitsCard({super.key, required this.productId});

  final int productId;

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    if (!catalog.hasProfile) return const SizedBox.shrink();
    final blacklisted = catalog.isBlacklisted(productId);
    final rec = catalog.recommendationFor(productId);
    final lines = <(IconData, Color, String)>[
      if (blacklisted)
        (
          Icons.block,
          AppColors.sale,
          tr('Есть компоненты из вашего чёрного списка'),
        )
      else if (rec != null)
        for (final r in _dedupe(rec.reasons))
          (
            switch (r.type) {
              MatchReasonType.previousReaction ||
              MatchReasonType.sharedIngredient ||
              MatchReasonType.shadeOff ||
              MatchReasonType.skinShadeOff => Icons.info_outline,
              MatchReasonType.owned => Icons.shopping_bag_outlined,
              _ => Icons.check_circle_outline,
            },
            switch (r.type) {
              MatchReasonType.previousReaction ||
              MatchReasonType.sharedIngredient ||
              MatchReasonType.shadeOff ||
              MatchReasonType.skinShadeOff => AppColors.sale,
              MatchReasonType.owned => context.pal.accent,
              _ => AppColors.success,
            },
            reasonText(r),
          ),
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
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
                Icon(Icons.favorite, size: 18, color: context.pal.accent),
                const SizedBox(width: 8),
                // one line: shrinks a little instead of leaving "вам" alone
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      tr('Почему это подходит вам'),
                      maxLines: 1,
                      style: AppTextStyles.subtitle,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (rec != null && !blacklisted)
                  Text(
                    trf('{n}% совпадение', {'n': rec.matchPercent}),
                    style: AppTextStyles.small.copyWith(
                      color: context.pal.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(l.$1, size: 16, color: l.$2),
                    const SizedBox(width: 8),
                    Expanded(child: Text(l.$3, style: AppTextStyles.small)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  static List<MatchReason> _dedupe(List<MatchReason> reasons) {
    final seen = <String>{};
    return [
      for (final r in reasons)
        if (seen.add('${r.type.name}:${r.detail}')) r,
    ];
  }

  static String reasonText(MatchReason r) {
    final detail = r.detail == null ? '' : tr(r.detail!);
    switch (r.type) {
      case MatchReasonType.colorType:
        return trf('Подходит вашему цветотипу: {v}', {'v': detail});
      case MatchReasonType.undertone:
        return trf('Подходит вашему подтону: {v}', {'v': detail});
      case MatchReasonType.skinType:
        return trf('Рекомендован для типа кожи: {v}', {'v': detail});
      case MatchReasonType.concern:
        return trf('Помогает при проблеме: {v}', {'v': detail});
      case MatchReasonType.gentle:
        return tr('Мягкий состав, без раздражающих компонентов');
      case MatchReasonType.noBlacklist:
        return tr('Нет активных компонентов из вашего чёрного списка');
      case MatchReasonType.preference:
        return trf('Соответствует вашему предпочтению: {v}', {'v': detail});
      case MatchReasonType.previousReaction:
        return trf(
          'Вы отмечали реакцию на это средство (тяжесть {v} из 5), поэтому оно ниже в рекомендациях',
          {'v': r.detail},
        );
      case MatchReasonType.sharedIngredient:
        return trf(
          'Содержит «{v}», который есть и в средствах с вашими реакциями (возможно, совпадение)',
          {'v': detail},
        );
      case MatchReasonType.owned:
        return tr('Это средство уже есть в вашей косметичке');
      case MatchReasonType.shadeFit:
        return trf('Оттенок близок к вашей палитре: {v}', {'v': detail});
      case MatchReasonType.shadeOff:
        return trf('Оттенок ближе к палитре «{v}»: вам могут подойти другие', {
          'v': detail,
        });
      case MatchReasonType.skinShade:
        return trf('Оттенок близок к вашему тону кожи: {v}', {'v': detail});
      case MatchReasonType.skinShadeOff:
        return trf('Оттенок может не совпасть с вашим тоном кожи: {v}', {
          'v': detail,
        });
    }
  }
}
