import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/models/safety_models.dart';
import 'package:cosmetix/providers/catalog_provider.dart';
import 'package:cosmetix/providers/safety_provider.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/common_widgets.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';
import 'package:cosmetix/widgets/product_art.dart';

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key, required this.productId});

  final int productId;

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  IngredientAnalysis? _analysis;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    context
        .read<SafetyProvider>()
        .analyze(widget.productId)
        .then((a) {
          if (mounted) {
            setState(() {
              _analysis = a;
              _loading = false;
            });
          }
        })
        .catchError((_) {
          if (mounted) setState(() => _loading = false);
        });
  }

  static Color _dot(int risk) => risk >= 2
      ? AppColors.danger
      : risk == 1
      ? AppColors.warning
      : AppColors.success;

  @override
  Widget build(BuildContext context) {
    final product = context.watch<CatalogProvider>().byId(widget.productId);
    final pal = context.pal;
    final a = _analysis;

    return PageScaffold(
      title: tr('Анализ состава'),
      bigTitle: true,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : a == null || product == null
          ? EmptyState(
              icon: Icons.science_outlined,
              title: tr('Состав недоступен'),
              subtitle: tr('Не удалось загрузить состав этого товара'),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 52,
                      height: 44,
                      child: ProductArt(
                        art: product.art,
                        color: product.color,
                        radius: 10,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.brand,
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.primaryDark,
                            ),
                          ),
                          Text(tr(product.name), style: AppTextStyles.bodyBold),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AppCard(
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: a.scoreColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          a.score.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: a.scoreColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.headline, style: AppTextStyles.subtitle),
                            const SizedBox(height: 2),
                            Text(
                              a.summary,
                              style: AppTextStyles.small.copyWith(
                                color: pal.subtext,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (a.blacklistHits.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  AppCard(
                    color: AppColors.saleSoft,
                    borderColor: AppColors.danger.withValues(alpha: 0.3),
                    onTap: () =>
                        Navigator.pushNamed(context, AppRoutes.blacklist),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('Есть компоненты из чёрного списка'),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.sale,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          trf(
                            'В составе найдено: {v0}. Нажмите, чтобы изменить чёрный список.',
                            {'v0': a.blacklistHits.map(tr).join(', ')},
                          ),
                          style: AppTextStyles.small,
                        ),
                      ],
                    ),
                  ),
                ],
                if (a.allergens.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  AppCard(
                    color: AppColors.saleSoft,
                    borderColor: Colors.transparent,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('Потенциальные аллергены'),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.sale,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          trf(
                            'Продукт содержит: {v0}. Людям с высокой чувствительностью рекомендуется тест на сгибе локтя.',
                            {
                              'v0': a.allergens
                                  .map((e) => tr(e.name).split(' / ').first)
                                  .join(', '),
                            },
                          ),
                          style: AppTextStyles.small,
                        ),
                      ],
                    ),
                  ),
                ],
                SectionTitle(tr('Список ингредиентов')),
                for (final i in a.ingredients)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(tr(i.name), style: AppTextStyles.bodyBold),
                                Text(
                                  tr(i.description),
                                  style: AppTextStyles.caption.copyWith(
                                    color: pal.subtext,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: _dot(i.risk),
                              shape: BoxShape.circle,
                            ),
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
