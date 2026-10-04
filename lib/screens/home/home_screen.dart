import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/providers/auth_provider.dart';
import 'package:cosmetix/providers/catalog_provider.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/routes/route_args.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/common_widgets.dart';
import 'package:cosmetix/widgets/product_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const _categories = [
    ('Макияж', 'cat_makeup'),
    ('Уход за лицом', 'cat_care'),
    ('Парфюмерия', 'cat_perfume'),
    ('Тело и ванна', 'cat_body'),
    ('Волосы', 'cat_hair'),
    ('Подарки', 'cat_gift'),
  ];

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final pal = context.pal;
    final recommended = catalog.recommendedForYou();

    return SafeArea(
      child: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => catalog.load(_userId(context)),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [
            // search entry
            InkWell(
              onTap: () => Navigator.pushNamed(context, AppRoutes.search),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: pal.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: pal.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, color: pal.subtext),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        tr('Поиск брендов, косметики, оттенков...'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: pal.subtext, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const _Banner(),
            const SizedBox(height: 12),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              radius: 20,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  for (final c in _categories)
                    Tooltip(
                      message: tr(c.$1),
                      child: InkWell(
                        onTap: () => Navigator.pushNamed(
                          context,
                          AppRoutes.catalog,
                          arguments: CatalogArgs(category: c.$1),
                        ),
                        customBorder: const CircleBorder(),
                        child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: ClipOval(
                            child: Image.asset(
                              'assets/photos/${c.$2}.jpg',
                              width: 36,
                              height: 36,
                              fit: BoxFit.cover,
                              cacheWidth: 120,
                              errorBuilder: (_, _, _) => const SizedBox(
                                width: 36,
                                height: 36,
                                child: Icon(
                                  Icons.spa_outlined,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (recommended.isNotEmpty) ...[
              SectionTitle(
                tr('Рекомендуем вам'),
                trailing: LinkText(
                  tr('Все'),
                  onTap: () => Navigator.pushNamed(
                    context,
                    AppRoutes.catalog,
                    arguments: const CatalogArgs(),
                  ),
                ),
              ),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: productGridDelegate(context, extent: 262),
                itemCount: recommended.length,
                itemBuilder: (context, i) => _card(
                  context,
                  catalog,
                  recommended[i].product,
                  match: recommended[i].matchPercent,
                ),
              ),
            ],
            SectionTitle(
              tr('Популярное'),
              trailing: LinkText(
                tr('Весь каталог'),
                onTap: () => Navigator.pushNamed(
                  context,
                  AppRoutes.catalog,
                  arguments: const CatalogArgs(),
                ),
              ),
            ),
            if (catalog.loading && catalog.products.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (catalog.error != null)
              ErrorState(
                message: catalog.error!,
                onRetry: () => catalog.load(_userId(context)),
              )
            else if (catalog.products.isEmpty)
              EmptyState(
                icon: Icons.inventory_2_outlined,
                title: tr('Каталог пуст'),
                subtitle: tr('Товары пока не добавлены'),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: productGridDelegate(context, extent: 240),
                itemCount: catalog.featured.length,
                itemBuilder: (context, i) =>
                    _card(context, catalog, catalog.featured[i]),
              ),
          ],
        ),
      ),
    );
  }

  static int _userId(BuildContext context) =>
      context.read<AuthProvider>().userId;

  Widget _card(
    BuildContext context,
    CatalogProvider catalog,
    Product p, {
    int? match,
  }) => ProductCard(
    product: p,
    footer: match == null ? null : MatchBadge(percent: match),
    onTap: () =>
        Navigator.pushNamed(context, AppRoutes.product, arguments: p.id),
    onFavorite: () async {
      final state = await catalog.toggleFavorite(p.id);
      if (state != null && context.mounted) {
        showMessage(
          context,
          state ? tr('Добавлено в избранное') : tr('Удалено из избранного'),
          type: state ? MessageType.success : MessageType.info,
        );
      }
    },
  );
}

class _Banner extends StatelessWidget {
  const _Banner();

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.pushNamed(
        context,
        AppRoutes.catalog,
        arguments: const CatalogArgs(onlySale: true),
      ),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 175,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFFBFE0E6),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/photos/banner.jpg',
              fit: BoxFit.cover,
              cacheWidth: 900,
              errorBuilder: (_, _, _) => const SizedBox(),
            ),
            Positioned(
              right: 12,
              top: 12,
              left: 60,
              child: Align(
                alignment: Alignment.topRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.local_florist_outlined,
                        size: 16,
                        color: AppColors.primaryDark,
                      ),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          tr('Специальное предложение'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.small,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
