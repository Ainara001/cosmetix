import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/material.dart';

import 'package:cosmetix/core/constants/app_constants.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/core/utils/validators.dart';
import 'package:cosmetix/models/product_filter.dart';
import 'package:cosmetix/routes/route_args.dart';
import 'package:cosmetix/services/ingredient_catalog.dart';
import 'package:cosmetix/widgets/common_widgets.dart';
import 'package:cosmetix/widgets/custom_button.dart';
import 'package:cosmetix/widgets/custom_text_field.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';

/// Returns the chosen [ProductFilter] via Navigator.pop.
class FiltersScreen extends StatefulWidget {
  const FiltersScreen({super.key, required this.args});

  final FiltersArgs args;

  @override
  State<FiltersScreen> createState() => _FiltersScreenState();
}

class _FiltersScreenState extends State<FiltersScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _min;
  late final TextEditingController _max;
  late ProductFilter _filter;

  /// How many catalog products each ingredient group would match.
  late final Map<String, int> _counts;

  @override
  void initState() {
    super.initState();
    _filter = widget.args.initial;
    _counts = {
      for (final g in IngredientCatalog.groups)
        g.code: widget.args.products.where((p) {
          final has = IngredientCatalog.of(p).contains(g.code);
          return g.kind == IngredientKind.avoid
              ? p.inci.trim().isNotEmpty && !has
              : has;
        }).length,
    };
    _name = TextEditingController(text: _filter.name);
    _min = TextEditingController(text: '${_filter.minPrice}');
    _max = TextEditingController(text: '${_filter.maxPrice}');
  }

  @override
  void dispose() {
    _name.dispose();
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  int get _found => widget.args.products.where(_filter.matches).length;

  void _syncFromFields() {
    final min = int.tryParse(_min.text.trim()) ?? 0;
    final max = int.tryParse(_max.text.trim()) ?? AppConstants.maxPrice;
    setState(
      () => _filter = _filter.copyWith(
        name: _name.text,
        minPrice: min,
        maxPrice: max,
      ),
    );
  }

  void _reset() {
    setState(() {
      _filter = ProductFilter(zone: widget.args.initial.zone);
      _name.clear();
      _min.text = '0';
      _max.text = '${AppConstants.maxPrice}';
    });
    showMessage(context, tr('Фильтры сброшены'));
  }

  void _apply() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, _filter.copyWith(name: _name.text.trim()));
  }

  String? _priceValidator(String? v) {
    final base = Validators.amount(v);
    if (base != null) return base;
    final min = int.tryParse(_min.text.trim()) ?? 0;
    final max = int.tryParse(_max.text.trim()) ?? AppConstants.maxPrice;
    if (min > max) return tr('«От» больше «До»');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final sliderMin = _filter.minPrice
        .clamp(0, AppConstants.maxPrice)
        .toDouble();
    final sliderMax = _filter.maxPrice
        .clamp(0, AppConstants.maxPrice)
        .toDouble();
    final range = RangeValues(
      sliderMin <= sliderMax ? sliderMin : sliderMax,
      sliderMax,
    );

    return PageScaffold(
      title: tr('Фильтры'),
      bigTitle: true,
      showNav: false,
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Divider(color: AppColors.primary.withValues(alpha: 0.6), height: 1),
            const SizedBox(height: 10),
            Text(
              tr('Уточните параметры, чтобы быстрее найти нужный товар.'),
              style: AppTextStyles.small.copyWith(color: pal.subtext),
            ),
            const SizedBox(height: 14),
            CustomTextField(
              label: tr('Наименование'),
              hint: tr('Поиск по названию'),
              controller: _name,
              suffixIcon: Icon(Icons.search, color: pal.subtext),
              onChanged: (_) => _syncFromFields(),
              validator: (v) =>
                  (v ?? '').length > 60 ? tr('Слишком длинный запрос') : null,
            ),
            const SizedBox(height: 14),
            _label(tr('Категория')),
            DropdownButtonFormField<String?>(
              initialValue: _filter.category,
              isExpanded: true,
              decoration: const InputDecoration(),
              items: [
                DropdownMenuItem(value: null, child: Text(tr('Все категории'))),
                for (final c in AppConstants.categories)
                  DropdownMenuItem(value: c, child: Text(tr(c))),
              ],
              onChanged: (v) =>
                  setState(() => _filter = _filter.copyWith(category: v)),
            ),
            const SizedBox(height: 14),
            _label(tr('Статус')),
            DropdownButtonFormField<ProductStatus>(
              initialValue: _filter.status,
              isExpanded: true,
              decoration: const InputDecoration(),
              items: [
                for (final s in ProductStatus.values)
                  DropdownMenuItem(value: s, child: Text(tr(s.label))),
              ],
              onChanged: (v) => setState(
                () =>
                    _filter = _filter.copyWith(status: v ?? ProductStatus.any),
              ),
            ),
            const SizedBox(height: 14),
            ..._composition(),
            _label(tr('Диапазон цены')),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.salmon,
                inactiveTrackColor: AppColors.primarySoft,
                thumbColor: Colors.white,
                overlayColor: AppColors.primary.withValues(alpha: 0.15),
                trackHeight: 10,
                rangeThumbShape: const RoundRangeSliderThumbShape(
                  enabledThumbRadius: 9,
                ),
              ),
              child: RangeSlider(
                values: range,
                min: 0,
                max: AppConstants.maxPrice.toDouble(),
                divisions: 100,
                onChanged: (v) {
                  setState(() {
                    _filter = _filter.copyWith(
                      minPrice: v.start.round(),
                      maxPrice: v.end.round(),
                    );
                    _min.text = '${_filter.minPrice}';
                    _max.text = '${_filter.maxPrice}';
                  });
                },
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: CustomTextField(
                    label: tr('От'),
                    controller: _min,
                    keyboardType: TextInputType.number,
                    suffixIcon: Padding(
                      padding: EdgeInsets.only(right: 14),
                      child: Center(widthFactor: 1, child: Text(tr('тг'))),
                    ),
                    onChanged: (_) => _syncFromFields(),
                    validator: _priceValidator,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: CustomTextField(
                    label: tr('До'),
                    controller: _max,
                    keyboardType: TextInputType.number,
                    suffixIcon: Padding(
                      padding: EdgeInsets.only(right: 14),
                      child: Center(widthFactor: 1, child: Text(tr('тг'))),
                    ),
                    onChanged: (_) => _syncFromFields(),
                    validator: _priceValidator,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _found == 0
                    ? tr('Подходящих товаров не найдено')
                    : trf('Будет найдено примерно {_found} товаров', {
                        '_found': _found,
                      }),
                style: TextStyle(
                  fontSize: 13,
                  color: _found == 0 ? AppColors.sale : AppColors.primaryDark,
                ),
              ),
            ),
            const SizedBox(height: 16),
            CustomButton(label: tr('Применить'), onPressed: _apply),
            const SizedBox(height: 12),
            CustomButton(
              label: tr('Сбросить'),
              outlined: true,
              onPressed: _reset,
            ),
          ],
        ),
      ),
    );
  }

  void _toggleIngredient(IngredientGroup g) {
    final avoid = g.kind == IngredientKind.avoid;
    final set = {
      ...(avoid ? _filter.withoutIngredients : _filter.withIngredients),
    };
    if (!set.add(g.code)) set.remove(g.code);
    setState(
      () => _filter = avoid
          ? _filter.copyWith(withoutIngredients: set)
          : _filter.copyWith(withIngredients: set),
    );
  }

  /// "Composition" block: acids, actives and "free of" choices, matched
  /// against the published INCI list of every product.
  List<Widget> _composition() {
    final pal = context.pal;
    Widget group(IngredientKind kind) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(kind.label),
            style: AppTextStyles.caption.copyWith(color: pal.subtext),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final g in IngredientCatalog.ofKind(kind))
                Opacity(
                  opacity: (_counts[g.code] ?? 0) == 0 ? 0.5 : 1,
                  child: AppChip(
                    label: '${tr(g.label)} · ${_counts[g.code] ?? 0}',
                    selected: kind == IngredientKind.avoid
                        ? _filter.withoutIngredients.contains(g.code)
                        : _filter.withIngredients.contains(g.code),
                    onTap: () => _toggleIngredient(g),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
    return [
      _label(tr('Состав')),
      Text(
        tr(
          'Ищем по опубликованному списку INCI. Число рядом: сколько товаров подходит.',
        ),
        style: AppTextStyles.caption.copyWith(color: pal.subtext),
      ),
      const SizedBox(height: 8),
      group(IngredientKind.acid),
      group(IngredientKind.active),
      if (_filter.withIngredients.length > 1)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Expanded(
                child: AppChip(
                  label: tr('Все выбранные'),
                  selected: !_filter.anyIngredient,
                  onTap: () => setState(
                    () => _filter = _filter.copyWith(anyIngredient: false),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppChip(
                  label: tr('Любой из выбранных'),
                  selected: _filter.anyIngredient,
                  onTap: () => setState(
                    () => _filter = _filter.copyWith(anyIngredient: true),
                  ),
                ),
              ),
            ],
          ),
        ),
      group(IngredientKind.avoid),
      const SizedBox(height: 4),
    ];
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: AppTextStyles.small.copyWith(color: context.pal.subtext),
    ),
  );
}
