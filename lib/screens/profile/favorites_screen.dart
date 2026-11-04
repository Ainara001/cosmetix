import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/providers/catalog_provider.dart';
import 'package:cosmetix/providers/settings_provider.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/routes/route_args.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/common_widgets.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';
import 'package:cosmetix/widgets/product_art.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final settings = context.watch<SettingsProvider>();
    final fmt = settings.priceText;
    final pal = context.pal;
    final favorites = catalog.favorites;

    return PageScaffold(
      title: tr('Избранное'),
      bigTitle: true,
      child: favorites.isEmpty
          ? EmptyState(
              icon: Icons.favorite_border,
              title: tr('В избранном пока пусто'),
              subtitle: tr(
                'Нажмите на сердечко у товара, чтобы сохранить его здесь',
              ),
              actionLabel: tr('Перейти в каталог'),
              onAction: () => Navigator.pushNamed(
                context,
                AppRoutes.catalog,
                arguments: const CatalogArgs(),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                for (final p in favorites)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      padding: const EdgeInsets.all(10),
                      onTap: () => Navigator.pushNamed(
                        context,
                        AppRoutes.product,
                        arguments: p.id,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 70,
                            height: 56,
                            child: ProductArt(
                              art: p.art,
                              color: p.color,
                              radius: 10,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.brand,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: pal.subtext,
                                  ),
                                ),
                                Text(
                                  tr(p.name),
                                  maxLines:
                                      3, // whole words, no cut in the middle
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.bodyBold,
                                ),
                                Text(
                                  fmt(p.price),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: context.pal.accent,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: tr('Убрать из избранного'),
                            onPressed: () async {
                              final catalogProvider = context
                                  .read<CatalogProvider>();
                              await catalogProvider.toggleFavorite(p.id);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context)
                                ..hideCurrentSnackBar()
                                ..showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      trf('«{v0}» удалён из избранного', {
                                        'v0': tr(p.name),
                                      }),
                                    ),
                                    action: SnackBarAction(
                                      label: tr('Отменить'),
                                      onPressed: () =>
                                          catalogProvider.toggleFavorite(p.id),
                                    ),
                                  ),
                                );
                            },
                            icon: Icon(
                              Icons.favorite,
                              color: context.pal.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                AppCard(
                  color: context.pal.pinkSoft,
                  borderColor: Colors.transparent,
                  onTap: settings.pushEnabled
                      ? null
                      : () => Navigator.pushNamed(context, AppRoutes.settings),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('Уведомления о скидках'),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: context.pal.accent,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        settings.pushEnabled
                            ? tr(
                                'Мы пришлём вам уведомление, когда цены на избранные товары снизятся.',
                              )
                            : tr(
                                'Уведомления выключены. Нажмите, чтобы включить их в настройках.',
                              ),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6E5A60),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
