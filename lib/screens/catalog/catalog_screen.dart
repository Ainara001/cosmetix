import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/constants/app_constants.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/models/product_filter.dart';
import 'package:cosmetix/providers/auth_provider.dart';
import 'package:cosmetix/providers/catalog_provider.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/routes/route_args.dart';
import 'package:cosmetix/widgets/common_widgets.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';
import 'package:cosmetix/widgets/product_card.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key, this.args = const CatalogArgs()});

  final CatalogArgs args;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  late final TextEditingController _search;
  late ProductFilter _filter;
  ProductSort _sort = ProductSort.newest;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: widget.args.query);
    _filter = ProductFilter(
      name: widget.args.query,
      category: widget.args.category,
      zone: widget.args.zone,
      status: widget.args.onlySale ? ProductStatus.sale : ProductStatus.any,
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _openFilters(CatalogProvider catalog) async {
    final picked = await Navigator.pushNamed<Object?>(
      context,
      AppRoutes.filters,
      arguments: FiltersArgs(initial: _filter, products: catalog.products),
    );
    if (picked is! ProductFilter || !mounted) return;
    setState(() {
      _filter = picked;
      _search.text = picked.name;
    });
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final pal = context.pal;
    final items = ProductFilter.apply(catalog.products, _filter, _sort);
    final hasFilters =
        _filter.category != null ||
        _filter.status != ProductStatus.any ||
        _filter.minPrice > 0 ||
        _filter.maxPrice < AppConstants.maxPrice;

    return PageScaffold(
      title: 'Каталог',
      bigTitle: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _search,
              inputFormatters: [LengthLimitingTextInputFormatter(60)],
              textInputAction: TextInputAction.search,
              onChanged: (v) =>
                  setState(() => _filter = _filter.copyWith(name: v)),
              onSubmitted: (v) => context.read<CatalogProvider>().addHistory(v),
              decoration: InputDecoration(
                hintText: 'Поиск брендов, косметики, оттенков...',
                prefixIcon: Icon(Icons.search, color: pal.subtext),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Очистить',
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => setState(() {
                          _search.clear();
                          _filter = _filter.copyWith(name: '');
                        }),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                AppChip(
                  label: 'Все',
                  selected: _filter.zone == null,
                  onTap: () =>
                      setState(() => _filter = _filter.copyWith(zone: null)),
                ),
                for (final z in AppConstants.zones) ...[
                  const SizedBox(width: 8),
                  AppChip(
                    label: z,
                    selected: _filter.zone == z,
                    onTap: () =>
                        setState(() => _filter = _filter.copyWith(zone: z)),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 0),
            child: Row(
              children: [
                PopupMenuButton<ProductSort>(
                  tooltip: 'Сортировка',
                  initialValue: _sort,
                  onSelected: (v) => setState(() => _sort = v),
                  itemBuilder: (_) => [
                    for (final s in ProductSort.values)
                      PopupMenuItem(value: s, child: Text(s.label)),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        const Icon(Icons.arrow_drop_down, size: 20),
                        Text(_sort.label, style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _openFilters(catalog),
                  icon: Badge(
                    isLabelVisible: hasFilters,
                    smallSize: 8,
                    backgroundColor: AppColors.sale,
                    child: Icon(Icons.filter_alt_outlined, color: pal.text),
                  ),
                  label: Text('Фильтры', style: TextStyle(color: pal.text)),
                ),
              ],
            ),
          ),
          Expanded(child: _body(catalog, items)),
        ],
      ),
    );
  }

  Widget _body(CatalogProvider catalog, List items) {
    if (catalog.loading && catalog.products.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (catalog.error != null) {
      return ErrorState(
        message: catalog.error!,
        onRetry: () => catalog.load(context.read<AuthProvider>().userId),
      );
    }
    if (items.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: 'Ничего не найдено',
        subtitle: 'По вашему запросу товаров нет. Измените поиск или фильтры.',
        actionLabel: 'Сбросить фильтры',
        onAction: () => setState(() {
          _filter = const ProductFilter();
          _search.clear();
        }),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      gridDelegate: productGridDelegate(context),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final p = items[i];
        return ProductCard(
          product: p,
          onTap: () =>
              Navigator.pushNamed(context, AppRoutes.product, arguments: p.id),
          onFavorite: () async {
            final state = await catalog.toggleFavorite(p.id);
            if (state != null && context.mounted) {
              showMessage(
                context,
                state ? 'Добавлено в избранное' : 'Удалено из избранного',
                type: state ? MessageType.success : MessageType.info,
              );
            }
          },
        );
      },
    );
  }
}
