import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/providers/auth_provider.dart';
import 'package:cosmetix/providers/catalog_provider.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/routes/route_args.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/common_widgets.dart';
import 'package:cosmetix/widgets/product_art.dart';
import 'package:cosmetix/widgets/product_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const _categories = [
    ('Макияж', Icons.brush_outlined),
    ('Уход за лицом', Icons.spa_outlined),
    ('Парфюмерия', Icons.water_drop_outlined),
    ('Тело и ванна', Icons.bathtub_outlined),
    ('Волосы', Icons.content_cut),
    ('Подарки', Icons.card_giftcard),
  ];

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final pal = context.pal;

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
                height: 48,
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
                    Text(
                      'Поиск брендов, косметики, оттенков...',
                      style: TextStyle(color: pal.subtext, fontSize: 13),
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
                      message: c.$1,
                      child: InkWell(
                        onTap: () => Navigator.pushNamed(
                          context,
                          AppRoutes.catalog,
                          arguments: CatalogArgs(category: c.$1),
                        ),
                        customBorder: const CircleBorder(),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            c.$2,
                            size: 28,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SectionTitle(
              'Популярное',
              trailing: LinkText(
                'Весь каталог',
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
              const EmptyState(
                icon: Icons.inventory_2_outlined,
                title: 'Каталог пуст',
                subtitle: 'Товары пока не добавлены',
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: productGridDelegate(extent: 240),
                itemCount: catalog.featured.length,
                itemBuilder: (context, i) {
                  final p = catalog.featured[i];
                  return ProductCard(
                    product: p,
                    onTap: () => Navigator.pushNamed(
                      context,
                      AppRoutes.product,
                      arguments: p.id,
                    ),
                    onFavorite: () async {
                      final state = await catalog.toggleFavorite(p.id);
                      if (state != null && context.mounted) {
                        showMessage(
                          context,
                          state
                              ? 'Добавлено в избранное'
                              : 'Удалено из избранного',
                          type: state ? MessageType.success : MessageType.info,
                        );
                      }
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  static int _userId(BuildContext context) =>
      context.read<AuthProvider>().userId;
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
        height: 150,
        decoration: BoxDecoration(
          color: const Color(0xFFBFE0E6),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Stack(
          children: [
            const Positioned(
              right: 14,
              top: 14,
              bottom: 14,
              width: 150,
              child: Row(
                children: [
                  Expanded(
                    child: ProductArt(
                      art: 'bottle',
                      color: 0xFF7CC0CF,
                      radius: 16,
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: ProductArt(
                      art: 'cream',
                      color: 0xFF4FA3B5,
                      radius: 16,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.local_florist_outlined,
                      size: 16,
                      color: AppColors.primaryDark,
                    ),
                    SizedBox(width: 6),
                    Text('Специальное предложение', style: AppTextStyles.small),
                  ],
                ),
              ),
            ),
            const Positioned(
              left: 14,
              bottom: 14,
              child: Text(
                'Скидки до 70%',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1E5560),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
