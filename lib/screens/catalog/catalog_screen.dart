import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/constants/app_constants.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/models/product_filter.dart';
import 'package:cosmetix/providers/ai_provider.dart';
import 'package:cosmetix/providers/auth_provider.dart';
import 'package:cosmetix/providers/catalog_provider.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/services/ai/recommendation_refiner.dart';
import 'package:cosmetix/services/ingredient_catalog.dart';
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

  /// Set once the user picks a sorting manually: it then wins for this visit.
  bool _sortChosen = false;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: widget.args.query);
    _filter = ProductFilter(
      name: widget.args.query,
      category: widget.args.category,
      zone: widget.args.zone,
      status: widget.args.onlySale ? ProductStatus.sale : ProductStatus.any,
      withIngredients: widget.args.ingredients,
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _aiBusy = false;

  /// Optional: asks the AI to refine the order of the personal picks. The
  /// catalog works the same without it.
  Future<void> _refineWithAi(CatalogProvider catalog) async {
    final ai = context.read<AiProvider>();
    if (!ai.ageAllowed) {
      showMessage(
        context,
        tr(
          'Уточнение с помощью ИИ доступно с 18 лет. Укажите год рождения в профиле.',
        ),
        type: MessageType.info,
      );
      return;
    }
    final refiner = context.read<RecommendationRefiner>();
    setState(() => _aiBusy = true);
    final ok = await catalog.refineWithAi(refiner);
    if (!mounted) return;
    setState(() => _aiBusy = false);
    if (ok) {
      showMessage(
        context,
        tr('Подбор уточнён с помощью ИИ'),
        type: MessageType.success,
      );
    } else {
      ai.markOffline('The AI server did not answer');
      showMessage(
        context,
        tr('ИИ сейчас недоступен — показан обычный персональный подбор.'),
        type: MessageType.info,
      );
    }
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

  void _toggleIngredient(String code) {
    final avoid = IngredientCatalog.byCode(code)?.kind == IngredientKind.avoid;
    final set = {
      ...(avoid ? _filter.withoutIngredients : _filter.withIngredients),
    };
    if (!set.add(code)) set.remove(code);
    setState(
      () => _filter = avoid
          ? _filter.copyWith(withoutIngredients: set)
          : _filter.copyWith(withIngredients: set),
    );
  }

  /// The composition filter is picked in "Фильтры"; the catalog only shows
  /// what is chosen (and lets you drop it), so the search area stays calm.
  Widget _ingredientRow() {
    final chosen = {..._filter.withIngredients, ..._filter.withoutIngredients};
    final codes = [...chosen];
    if (codes.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        height: 38,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  tr('Состав:'),
                  style: TextStyle(fontSize: 12, color: context.pal.subtext),
                ),
              ),
            ),
            for (final code in codes) ...[
              AppChip(
                label: tr(IngredientCatalog.byCode(code)!.label),
                selected: chosen.contains(code),
                onTap: () => _toggleIngredient(code),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }

  /// Under a card: the personal match and, while composition filters are
  /// on, which of the wanted ingredients the product really has.
  Widget? _cardFooter(Product p, int? match) {
    final found = [
      for (final g in IngredientCatalog.activesOf(p))
        if (_filter.withIngredients.contains(g.code)) tr(g.label),
    ];
    if (match == null && found.isEmpty) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (match != null) MatchBadge(percent: match),
        if (found.isNotEmpty)
          Text(
            found.join(', '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: context.pal.accent,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final pal = context.pal;
    final sort = _sortChosen
        ? _sort
        : (catalog.hasProfile ? ProductSort.forYou : ProductSort.newest);
    var items = ProductFilter.apply(catalog.products, _filter, sort);
    var hiddenByAge = 0;
    final matches = <int, int>{};
    if (sort == ProductSort.forYou) {
      // search/filters first, then blacklist exclusion and personal ranking
      hiddenByAge = catalog.hiddenByAge(items);
      final ranked = catalog.recommend(items);
      items = [for (final r in ranked) r.product];
      for (final r in ranked) {
        matches[r.product.id] = r.matchPercent;
      }
    }
    // one tile per line (palette 00, 01, 02... is one palette with a choice)
    items = catalog.collapseLines(items);
    final hasFilters =
        _filter.category != null ||
        _filter.status != ProductStatus.any ||
        _filter.minPrice > 0 ||
        _filter.maxPrice < AppConstants.maxPrice ||
        _filter.hasIngredientFilter;

    return PageScaffold(
      title: tr('Каталог'),
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
                hintText: tr('Поиск брендов, косметики, оттенков...'),
                prefixIcon: Icon(Icons.search, color: pal.subtext),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: tr('Очистить'),
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
                  label: tr('Все'),
                  selected: _filter.zone == null,
                  onTap: () =>
                      setState(() => _filter = _filter.copyWith(zone: null)),
                ),
                for (final z in AppConstants.zones) ...[
                  const SizedBox(width: 8),
                  AppChip(
                    label: tr(z),
                    selected: _filter.zone == z,
                    onTap: () =>
                        setState(() => _filter = _filter.copyWith(zone: z)),
                  ),
                ],
              ],
            ),
          ),
          _ingredientRow(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 0),
            child: Row(
              children: [
                Flexible(
                  child: PopupMenuButton<ProductSort>(
                    tooltip: tr('Сортировка'),
                    initialValue: sort,
                    onSelected: (v) => setState(() {
                      _sort = v;
                      _sortChosen = true;
                    }),
                    itemBuilder: (_) => [
                      for (final s in ProductSort.catalogOptions(
                        hasProfile: catalog.hasProfile,
                      ))
                        PopupMenuItem(value: s, child: Text(tr(s.label))),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.arrow_drop_down, size: 20),
                          Flexible(
                            child: Text(
                              tr(sort.label),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                if (sort == ProductSort.forYou)
                  Tooltip(
                    message: tr('Уточнить подбор с ИИ'),
                    child: TextButton.icon(
                      icon: _aiBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              catalog.hasAiOrder
                                  ? Icons.auto_awesome
                                  : Icons.auto_awesome_outlined,
                              color: context.pal.accent,
                            ),
                      label: Text(
                        tr('ИИ'),
                        style: TextStyle(color: context.pal.accent),
                      ),
                      onPressed: _aiBusy ? null : () => _refineWithAi(catalog),
                    ),
                  ),
                TextButton.icon(
                  onPressed: () => _openFilters(catalog),
                  icon: Badge(
                    isLabelVisible: hasFilters,
                    smallSize: 8,
                    backgroundColor: AppColors.sale,
                    child: Icon(Icons.filter_alt_outlined, color: pal.text),
                  ),
                  label: Text(tr('Фильтры'), style: TextStyle(color: pal.text)),
                ),
              ],
            ),
          ),
          if (hiddenByAge > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                trf(
                  'Скрыто по возрасту: {n}. Ретиноиды и бензоилпероксид детям до 12 лет не предлагают.',
                  {'n': hiddenByAge},
                ),
                style: AppTextStyles.small.copyWith(color: pal.subtext),
              ),
            ),
          Expanded(child: _body(catalog, items, matches)),
        ],
      ),
    );
  }

  Widget _body(CatalogProvider catalog, List items, Map<int, int> matches) {
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
        title: tr('Ничего не найдено'),
        subtitle: tr(
          'По вашему запросу товаров нет. Измените поиск или фильтры.',
        ),
        actionLabel: tr('Сбросить фильтры'),
        onAction: () => setState(() {
          _filter = const ProductFilter();
          _search.clear();
        }),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      gridDelegate: productGridDelegate(
        context,
        extent:
            (matches.isEmpty ? 250 : 270) +
            (_filter.withIngredients.isEmpty ? 0 : 22),
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final p = items[i];
        final match = matches[p.id];
        return lineCard(
          catalog,
          p,
          footer: _cardFooter(p, match),
          onTap: () =>
              Navigator.pushNamed(context, AppRoutes.product, arguments: p.id),
          onFavorite: () async {
            final state = await catalog.toggleFavorite(p.id);
            if (state != null && context.mounted) {
              showMessage(
                context,
                state
                    ? tr('Добавлено в избранное')
                    : tr('Удалено из избранного'),
                type: state ? MessageType.success : MessageType.info,
              );
            }
          },
        );
      },
    );
  }
}
