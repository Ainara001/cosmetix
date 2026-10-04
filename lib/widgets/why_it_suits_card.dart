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
          (Icons.check_circle_outline, AppColors.success, _text(r)),
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: AppCard(
        color: AppColors.primarySoft,
        borderColor: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.favorite,
                  size: 18,
                  color: AppColors.primaryDark,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('Почему это подходит вам'),
                    style: AppTextStyles.subtitle,
                  ),
                ),
                if (rec != null && !blacklisted)
                  Text(
                    trf('{n}% совпадение', {'n': rec.matchPercent}),
                    style: AppTextStyles.small.copyWith(
                      color: AppColors.primaryDark,
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

  static String _text(MatchReason r) {
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
    }
  }
}
