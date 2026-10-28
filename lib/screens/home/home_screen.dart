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

  /// (catalog category, icon, short caption under the icon)
  static const _categories = [
    ('Макияж', 'cat_makeup', 'Макияж'),
    ('Уход за лицом', 'cat_care', 'Уход'),
    ('Парфюмерия', 'cat_perfume', 'Парфюм'),
    ('Тело и ванна', 'cat_body', 'Тело'),
    ('Волосы', 'cat_hair', 'Волосы'),
    ('Подарки', 'cat_gift', 'Подарки'),
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
            // shopping first: categories, then the offer, then the personal tools
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
              radius: 20,
              child: Row(
                children: [
                  for (final c in _categories)
                    Expanded(
                      child: Tooltip(
                        message: tr(c.$1),
                        child: InkWell(
                          onTap: () => Navigator.pushNamed(
                            context,
                            AppRoutes.catalog,
                            arguments: CatalogArgs(category: c.$1),
                          ),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Image.asset(
                                  'assets/icons/${c.$2}.png',
                                  width: 34,
                                  height: 34,
                                  cacheWidth: 136,
                                  errorBuilder: (_, _, _) => const Icon(
                                    Icons.spa_outlined,
                                    size: 34,
                                    color: AppColors.primaryDark,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  tr(c.$3),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: AppTextStyles.caption,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const _Banner(),
            const SizedBox(height: 12),
            const _QuickAccess(),
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
        height: 140,
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
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: AppColors.primaryDark,
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

/// Six shortcuts to the main personal tools (search is the field above).
class _QuickAccess extends StatelessWidget {
  const _QuickAccess();

  @override
  Widget build(BuildContext context) {
    final hasProfile = context.watch<CatalogProvider>().hasProfile;
    final items = <(IconData, String, VoidCallback)>[
      (
        Icons.face_retouching_natural_outlined,
        'Бьюти-профиль',
        () => Navigator.pushNamed(context, AppRoutes.beautyProfile),
      ),
      (
        Icons.auto_awesome_outlined,
        'Рекомендации',
        // without a Beauty Profile there is nothing to personalize yet
        () => hasProfile
            ? Navigator.pushNamed(
                context,
                AppRoutes.catalog,
                arguments: const CatalogArgs(),
              )
            : Navigator.pushNamed(context, AppRoutes.colorTest),
      ),
      (
        Icons.document_scanner_outlined,
        'Проверка состава',
        () => Navigator.pushNamed(context, AppRoutes.scan),
      ),
      (
        Icons.healing_outlined,
        'Дневник реакций',
        () => Navigator.pushNamed(context, AppRoutes.reactions),
      ),
      (
        Icons.wb_twilight_outlined,
        'Мой уход',
        () => Navigator.pushNamed(context, AppRoutes.care),
      ),
      (
        Icons.shopping_bag_outlined,
        'Косметичка',
        () => Navigator.pushNamed(context, AppRoutes.bag),
      ),
    ];
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        // icon + padding are fixed, the two label lines grow with the system
        // font size, so the tile never overflows
        mainAxisExtent: 60 + MediaQuery.textScalerOf(context).scale(32),
      ),
      children: [
        for (final i in items)
          AppCard(
            onTap: i.$3,
            radius: 16,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: AppColors.primarySoft,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(i.$1, size: 20, color: AppColors.primaryDark),
                ),
                const SizedBox(height: 6),
                Text(
                  tr(i.$2),
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
