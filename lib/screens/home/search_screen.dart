import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/providers/catalog_provider.dart';
import 'package:cosmetix/providers/settings_provider.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/routes/route_args.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/common_widgets.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';
import 'package:cosmetix/widgets/product_art.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();

  static const _categories = [
    ('Макияж', Icons.brush_outlined),
    ('Уход за лицом', Icons.spa_outlined),
    ('Парфюмерия', Icons.water_drop_outlined),
    ('Тело и ванна', Icons.bathtub_outlined),
    ('Волосы', Icons.content_cut),
    ('Подарки', Icons.card_giftcard),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String query) {
    final text = query.trim();
    if (text.isEmpty) return;
    context.read<CatalogProvider>().addHistory(text);
    Navigator.pushNamed(
      context,
      AppRoutes.catalog,
      arguments: CatalogArgs(query: text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final pal = context.pal;
    final query = _controller.text.trim().toLowerCase();
    final found = query.isEmpty
        ? const <Product>[]
        : catalog.products
              .where(
                (p) => '${p.brand} ${p.name}'.toLowerCase().contains(query),
              )
              .toList();
    // with a Beauty Profile the suggestions are personal: no blacklisted
    // products, best match first (same rule as the catalog "For you" sort)
    final matches =
        (catalog.hasProfile
                ? [for (final r in catalog.recommend(found)) r.product]
                : found)
            .take(8)
            .toList();

    return PageScaffold(
      title: tr('Поиск'),
      bigTitle: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          TextField(
            controller: _controller,
            inputFormatters: [LengthLimitingTextInputFormatter(60)],
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(() {}),
            onSubmitted: _submit,
            decoration: InputDecoration(
              hintText: tr('Поиск брендов, косметики, оттенков...'),
              prefixIcon: Icon(Icons.search, color: pal.subtext),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: tr('Очистить'),
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => setState(_controller.clear),
                    ),
            ),
          ),
          if (query.isNotEmpty) ...[
            SectionTitle(trf('Результаты ({v0})', {'v0': matches.length})),
            if (matches.isEmpty)
              EmptyState(
                icon: Icons.search_off,
                title: tr('Ничего не найдено'),
                subtitle: tr('Попробуйте другой запрос или название бренда'),
              )
            else ...[
              for (final p in matches) _ProductRow(product: p),
              const SizedBox(height: 8),
              LinkText(
                tr('Показать все в каталоге'),
                onTap: () => _submit(_controller.text),
              ),
            ],
          ] else ...[
            if (catalog.history.isNotEmpty) ...[
              SectionTitle(
                tr('История поиска'),
                trailing: LinkText(
                  tr('Очистить'),
                  onTap: () => context.read<CatalogProvider>().clearHistory(),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final h in catalog.history)
                    InputChip(
                      label: Text(h, style: const TextStyle(fontSize: 12)),
                      backgroundColor: pal.surface,
                      side: BorderSide(color: pal.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      onPressed: () {
                        _controller.text = h;
                        _submit(h);
                      },
                      onDeleted: () =>
                          context.read<CatalogProvider>().removeHistory(h),
                    ),
                ],
              ),
            ],
            SectionTitle(tr('Популярные категории')),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.15,
              children: [
                for (final c in _categories)
                  AppCard(
                    onTap: () => Navigator.pushNamed(
                      context,
                      AppRoutes.catalog,
                      arguments: CatalogArgs(category: c.$1),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(c.$2, color: AppColors.primaryDark, size: 28),
                        const SizedBox(height: 6),
                        Text(
                          tr(c.$1),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: AppTextStyles.caption,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            SectionTitle(tr('Сейчас в тренде')),
            if (catalog.trending.isEmpty)
              Text(
                tr('Пока нет трендовых товаров'),
                style: TextStyle(color: pal.subtext),
              )
            else
              for (final p in catalog.trending) _ProductRow(product: p),
          ],
        ],
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final fmt = context.watch<SettingsProvider>().priceText;
    return InkWell(
      onTap: () => Navigator.pushNamed(
        context,
        AppRoutes.product,
        arguments: product.id,
      ),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              height: 48,
              child: ProductArt(
                art: product.art,
                color: product.color,
                radius: 10,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.brand,
                    style: TextStyle(fontSize: 10, color: pal.subtext),
                  ),
                  Text(
                    tr(product.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyBold,
                  ),
                  Text(
                    fmt(product.price),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: pal.subtext),
          ],
        ),
      ),
    );
  }
}
