import 'package:flutter/material.dart';

import 'package:cosmetix/core/constants/app_constants.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/core/utils/validators.dart';
import 'package:cosmetix/models/product_filter.dart';
import 'package:cosmetix/routes/route_args.dart';
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

  @override
  void initState() {
    super.initState();
    _filter = widget.args.initial;
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
    showMessage(context, 'Фильтры сброшены');
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
    if (min > max) return '«От» больше «До»';
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
      title: 'Фильтры',
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
              'Уточните параметры, чтобы быстрее найти нужный товар.',
              style: AppTextStyles.small.copyWith(color: pal.subtext),
            ),
            const SizedBox(height: 14),
            CustomTextField(
              label: 'Наименование',
              hint: 'Поиск по названию',
              controller: _name,
              suffixIcon: Icon(Icons.search, color: pal.subtext),
              onChanged: (_) => _syncFromFields(),
              validator: (v) =>
                  (v ?? '').length > 60 ? 'Слишком длинный запрос' : null,
            ),
            const SizedBox(height: 14),
            _label('Категория'),
            DropdownButtonFormField<String?>(
              initialValue: _filter.category,
              isExpanded: true,
              decoration: const InputDecoration(),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Все категории'),
                ),
                for (final c in AppConstants.categories)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) =>
                  setState(() => _filter = _filter.copyWith(category: v)),
            ),
            const SizedBox(height: 14),
            _label('Статус'),
            DropdownButtonFormField<ProductStatus>(
              initialValue: _filter.status,
              isExpanded: true,
              decoration: const InputDecoration(),
              items: [
                for (final s in ProductStatus.values)
                  DropdownMenuItem(value: s, child: Text(s.label)),
              ],
              onChanged: (v) => setState(
                () =>
                    _filter = _filter.copyWith(status: v ?? ProductStatus.any),
              ),
            ),
            const SizedBox(height: 14),
            _label('Диапазон цены'),
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
                    label: 'От',
                    controller: _min,
                    keyboardType: TextInputType.number,
                    suffixIcon: const Padding(
                      padding: EdgeInsets.only(right: 14),
                      child: Center(widthFactor: 1, child: Text('тг')),
                    ),
                    onChanged: (_) => _syncFromFields(),
                    validator: _priceValidator,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: CustomTextField(
                    label: 'До',
                    controller: _max,
                    keyboardType: TextInputType.number,
                    suffixIcon: const Padding(
                      padding: EdgeInsets.only(right: 14),
                      child: Center(widthFactor: 1, child: Text('тг')),
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
                    ? 'Подходящих товаров не найдено'
                    : 'Будет найдено примерно $_found товаров',
                style: TextStyle(
                  fontSize: 13,
                  color: _found == 0 ? AppColors.sale : AppColors.primaryDark,
                ),
              ),
            ),
            const SizedBox(height: 16),
            CustomButton(label: 'Применить', onPressed: _apply),
            const SizedBox(height: 12),
            CustomButton(label: 'Сбросить', outlined: true, onPressed: _reset),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: AppTextStyles.small.copyWith(color: context.pal.subtext),
    ),
  );
}
