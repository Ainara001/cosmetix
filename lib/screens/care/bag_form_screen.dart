import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/constants/app_constants.dart';
import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/formatters.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/models/care_models.dart';
import 'package:cosmetix/providers/care_provider.dart';
import 'package:cosmetix/providers/catalog_provider.dart';
import 'package:cosmetix/routes/route_args.dart';
import 'package:cosmetix/screens/care/bag_screen.dart';
import 'package:cosmetix/widgets/common_widgets.dart';
import 'package:cosmetix/widgets/custom_button.dart';
import 'package:cosmetix/widgets/custom_text_field.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';

/// Add / edit a product of the cosmetic bag.
class BagFormScreen extends StatefulWidget {
  const BagFormScreen({super.key, this.args = const BagFormArgs()});

  final BagFormArgs args;

  @override
  State<BagFormScreen> createState() => _BagFormScreenState();
}

class _BagFormScreenState extends State<BagFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _brand = TextEditingController();
  final _notes = TextEditingController();
  int? _catalogId;
  String? _category;
  DateTime? _purchased;
  DateTime? _opened;
  DateTime? _expires;
  int? _pao;
  bool _saving = false;
  MyProduct? _editing;

  @override
  void initState() {
    super.initState();
    final care = context.read<CareProvider>();
    final id = widget.args.id;
    if (id != null) {
      final p = care.byId(id);
      if (p != null) {
        _editing = p;
        _catalogId = p.productId;
        _name.text = p.name;
        _brand.text = p.brand;
        _notes.text = p.notes;
        _category = p.category.isEmpty ? null : p.category;
        _purchased = p.purchasedAt;
        _opened = p.openedAt;
        _expires = p.expiresAt;
        _pao = p.paoMonths;
      }
    } else if (widget.args.catalogProductId != null) {
      _pick(widget.args.catalogProductId);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Takes the name, brand and category from a catalog product.
  void _pick(int? productId) {
    setState(() => _catalogId = productId);
    if (productId == null) return;
    final p = context.read<CatalogProvider>().byId(productId);
    if (p == null) return;
    _name.text = tr(p.name);
    _brand.text = p.brand;
    _category = p.category;
  }

  MyProduct _build() => MyProduct(
    id: _editing?.id ?? 0,
    productId: _catalogId,
    name: _name.text,
    brand: _brand.text,
    category: _category ?? '',
    purchasedAt: _purchased,
    openedAt: _opened,
    paoMonths: _opened == null ? null : _pao,
    expiresAt: _expires,
    notes: _notes.text,
  );

  Future<DateTime?> _pickDate(
    DateTime? current, {
    required String help,
    required DateTime first,
    required DateTime last,
  }) {
    final now = DateTime.now();
    var initial = current ?? now;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: help,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      showMessage(context, tr('Проверьте поля формы'), type: MessageType.error);
      return;
    }
    setState(() => _saving = true);
    final care = context.read<CareProvider>();
    final error = await care.saveProduct(_build(), isNew: _editing == null);
    if (!mounted) return;
    if (error != null) {
      setState(() => _saving = false);
      showMessage(context, error, type: MessageType.error);
      return;
    }
    showMessage(
      context,
      _editing == null ? tr('Средство добавлено') : tr('Изменения сохранены'),
      type: MessageType.success,
    );
    Navigator.pop(context);
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      t,
      style: AppTextStyles.small.copyWith(color: context.pal.subtext),
    ),
  );

  Widget _dateField({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
    required VoidCallback onClear,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _label(label),
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: InputDecorator(
          decoration: InputDecoration(
            suffixIcon: value == null
                ? const Icon(Icons.calendar_today_outlined, size: 18)
                : IconButton(
                    tooltip: tr('Очистить дату'),
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: onClear,
                  ),
          ),
          child: Text(
            value == null ? tr('Не указана') : Formatters.date(value),
            style: TextStyle(color: value == null ? context.pal.subtext : null),
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final products = context.watch<CatalogProvider>().products;
    final today = DateTime.now();
    final first = DateTime(2015);

    return PageScaffold(
      title: _editing == null ? tr('Добавить средство') : tr('Моё средство'),
      showNav: false,
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            _label(tr('Выбрать из каталога (необязательно)')),
            DropdownButtonFormField<int?>(
              initialValue: products.any((p) => p.id == _catalogId)
                  ? _catalogId
                  : null,
              isExpanded: true,
              hint: Text(tr('Другое средство — ввести вручную')),
              items: [
                DropdownMenuItem<int?>(
                  value: null,
                  child: Text(tr('Другое средство — ввести вручную')),
                ),
                for (final p in products)
                  DropdownMenuItem<int?>(
                    value: p.id,
                    child: Text(
                      '${p.brand} — ${tr(p.name)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _pick,
            ),
            const SizedBox(height: 14),
            CustomTextField(
              label: tr('Название'),
              hint: tr('Например, увлажняющий крем'),
              controller: _name,
              maxLength: 80,
              validator: (v) => (v ?? '').trim().length < 2
                  ? tr('Введите название средства')
                  : null,
            ),
            const SizedBox(height: 14),
            CustomTextField(
              label: tr('Бренд (необязательно)'),
              controller: _brand,
              maxLength: 60,
            ),
            const SizedBox(height: 14),
            _label(tr('Категория')),
            DropdownButtonFormField<String>(
              initialValue: _category,
              isExpanded: true,
              hint: Text(tr('Выберите категорию')),
              items: [
                for (final c in AppConstants.categories)
                  DropdownMenuItem(value: c, child: Text(tr(c))),
              ],
              onChanged: (v) => setState(() => _category = v),
            ),
            const SizedBox(height: 14),
            _dateField(
              label: tr('Дата покупки'),
              value: _purchased,
              onTap: () async {
                final d = await _pickDate(
                  _purchased,
                  help: tr('Дата покупки'),
                  first: first,
                  last: today,
                );
                if (d != null) setState(() => _purchased = d);
              },
              onClear: () => setState(() => _purchased = null),
            ),
            const SizedBox(height: 14),
            _dateField(
              label: tr('Дата вскрытия'),
              value: _opened,
              onTap: () async {
                final d = await _pickDate(
                  _opened,
                  help: tr('Дата вскрытия'),
                  first: first,
                  last: today,
                );
                if (d != null) setState(() => _opened = d);
              },
              onClear: () => setState(() {
                _opened = null;
                _pao = null;
              }),
            ),
            if (_opened != null) ...[
              const SizedBox(height: 14),
              _label(tr('Срок после вскрытия (значок банки на упаковке)')),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AppChip(
                    label: tr('Не знаю'),
                    selected: _pao == null,
                    onTap: () => setState(() => _pao = null),
                  ),
                  for (final m in MyProduct.paoChoices)
                    AppChip(
                      label: '${m}M',
                      selected: _pao == m,
                      onTap: () => setState(() => _pao = m),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            _dateField(
              label: tr('Годен до (дата на упаковке)'),
              value: _expires,
              onTap: () async {
                final d = await _pickDate(
                  _expires,
                  help: tr('Годен до'),
                  first: DateTime(today.year - 1),
                  last: DateTime(today.year + 10),
                );
                if (d != null) setState(() => _expires = d);
              },
              onClear: () => setState(() => _expires = null),
            ),
            const SizedBox(height: 14),
            ExpiryChip(product: _build()),
            const SizedBox(height: 6),
            Text(
              tr(
                'Напоминание основано на данных упаковки, которые вы ввели. Это не медицинская рекомендация.',
              ),
              style: AppTextStyles.caption.copyWith(color: context.pal.subtext),
            ),
            const SizedBox(height: 14),
            CustomTextField(
              label: tr('Заметка (необязательно)'),
              controller: _notes,
              maxLines: 3,
              maxLength: 300,
            ),
            const SizedBox(height: 12),
            CustomButton(
              label: _editing == null
                  ? tr('Добавить в косметичку')
                  : tr('Сохранить изменения'),
              loading: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
