import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/constants/app_constants.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/formatters.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/core/utils/validators.dart';
import 'package:cosmetix/providers/catalog_provider.dart';
import 'package:cosmetix/providers/safety_provider.dart';
import 'package:cosmetix/widgets/custom_button.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';

/// Added screen: create / edit a skin reaction record.
class ReactionFormScreen extends StatefulWidget {
  const ReactionFormScreen({super.key, this.reactionId});

  final int? reactionId;

  @override
  State<ReactionFormScreen> createState() => _ReactionFormScreenState();
}

class _ReactionFormScreenState extends State<ReactionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _custom = TextEditingController();
  final _notes = TextEditingController();
  int? _productId;
  String? _type;
  int _severity = 2;
  DateTime _date = DateTime.now();
  bool _loading = true;
  bool _saving = false;

  bool get _editing => widget.reactionId != null;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (_editing) {
      final r = await context.read<SafetyProvider>().reactionById(
        widget.reactionId!,
      );
      if (r != null) {
        _productId = r.productId;
        _severity = r.severity;
        _date = r.date;
        _notes.text = r.notes;
        if (AppConstants.reactionTypes.contains(r.title)) {
          _type = r.title;
        } else {
          _type = 'Другое';
          _custom.text = r.title;
        }
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _custom.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(now) ? now : _date,
      firstDate: DateTime(2020),
      lastDate: now,
      helpText: 'Дата реакции',
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      showMessage(context, 'Проверьте поля формы', type: MessageType.error);
      return;
    }
    setState(() => _saving = true);
    final title = _type == 'Другое' ? _custom.text.trim() : _type!;
    try {
      await context.read<SafetyProvider>().saveReaction(
        id: widget.reactionId,
        productId: _productId!,
        title: title,
        severity: _severity,
        date: _date,
        notes: _notes.text,
      );
      if (!mounted) return;
      showMessage(
        context,
        _editing ? 'Запись обновлена' : 'Реакция добавлена в дневник',
        type: MessageType.success,
      );
      Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        showMessage(
          context,
          'Не удалось сохранить запись',
          type: MessageType.error,
        );
      }
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'Удалить запись?',
      message: 'Запись будет удалена из дневника реакций.',
      confirmLabel: 'Удалить',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final safety = context.read<SafetyProvider>();
    final r = await safety.reactionById(widget.reactionId!);
    if (r != null) await safety.deleteReaction(r);
    if (!mounted) return;
    showMessage(context, 'Запись удалена', type: MessageType.success);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final products = context.watch<CatalogProvider>().products;
    final pal = context.pal;

    return PageScaffold(
      title: _editing ? 'Редактировать реакцию' : 'Добавить реакцию',
      showNav: false,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  _label('Продукт'),
                  DropdownButtonFormField<int>(
                    initialValue: products.any((p) => p.id == _productId)
                        ? _productId
                        : null,
                    isExpanded: true,
                    hint: const Text('Выберите продукт'),
                    validator: (v) => v == null ? 'Выберите продукт' : null,
                    items: [
                      for (final p in products)
                        DropdownMenuItem(
                          value: p.id,
                          child: Text(
                            '${p.brand} — ${p.name}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _productId = v),
                  ),
                  const SizedBox(height: 14),
                  _label('Тип реакции'),
                  DropdownButtonFormField<String>(
                    initialValue: _type,
                    isExpanded: true,
                    hint: const Text('Выберите реакцию'),
                    validator: (v) => v == null ? 'Выберите тип реакции' : null,
                    items: [
                      for (final t in AppConstants.reactionTypes)
                        DropdownMenuItem(value: t, child: Text(t)),
                    ],
                    onChanged: (v) => setState(() => _type = v),
                  ),
                  if (_type == 'Другое') ...[
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _custom,
                      validator: (v) => Validators.text(
                        v,
                        min: 3,
                        max: 40,
                        field: 'Описание',
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Опишите реакцию',
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _label('Тяжесть: $_severity из 5'),
                  Row(
                    children: [
                      for (var i = 1; i <= 5; i++)
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _severity = i),
                            child: Container(
                              height: 36,
                              margin: EdgeInsets.only(right: i == 5 ? 0 : 6),
                              decoration: BoxDecoration(
                                color: i <= _severity
                                    ? AppColors.sale
                                    : pal.field,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '$i',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: i <= _severity
                                      ? Colors.white
                                      : pal.subtext,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _label('Дата'),
                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(16),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        suffixIcon: Icon(
                          Icons.calendar_today_outlined,
                          size: 18,
                        ),
                      ),
                      child: Text(Formatters.date(_date)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _label('Заметка (необязательно)'),
                  TextFormField(
                    controller: _notes,
                    maxLines: 3,
                    maxLength: 300,
                    validator: (v) =>
                        (v ?? '').length > 300 ? 'Максимум 300 символов' : null,
                    decoration: const InputDecoration(
                      hintText: 'Что вы почувствовали?',
                    ),
                  ),
                  const SizedBox(height: 12),
                  CustomButton(
                    label: _editing
                        ? 'Сохранить изменения'
                        : 'Добавить в дневник',
                    loading: _saving,
                    onPressed: _save,
                  ),
                  if (_editing) ...[
                    const SizedBox(height: 10),
                    CustomButton(
                      label: 'Удалить запись',
                      outlined: true,
                      color: AppColors.sale,
                      onPressed: _delete,
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      t,
      style: AppTextStyles.small.copyWith(color: context.pal.subtext),
    ),
  );
}
