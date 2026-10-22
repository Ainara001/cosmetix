import 'dart:io';

import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/constants/app_constants.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/app_paths.dart';
import 'package:cosmetix/core/utils/formatters.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/core/utils/validators.dart';
import 'package:cosmetix/models/safety_models.dart';
import 'package:cosmetix/providers/catalog_provider.dart';
import 'package:cosmetix/providers/safety_provider.dart';
import 'package:cosmetix/widgets/custom_button.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';
import 'package:cosmetix/widgets/reaction_history_list.dart';

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
  String? _photo;
  bool _photoChanged = false;
  List<ReactionChange> _history = const [];

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
        _photo = r.photoPath;
        if (AppConstants.reactionTypes.contains(r.title)) {
          _type = r.title;
        } else {
          _type = tr('Другое');
          _custom.text = r.title;
        }
      }
    }
    if (_editing && mounted) {
      _history = await context.read<SafetyProvider>().reactionHistory(
        widget.reactionId!,
      );
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(tr('Выбрать из галереи')),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(tr('Сделать снимок')),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final x = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1280,
        imageQuality: 85,
      );
      if (x != null && mounted) {
        setState(() {
          _photo = x.path;
          _photoChanged = true;
        });
      }
    } catch (_) {
      if (mounted) {
        showMessage(
          context,
          tr('Не удалось получить фото. Проверьте доступ к камере/галерее.'),
          type: MessageType.error,
        );
      }
    }
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
      helpText: tr('Дата реакции'),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      showMessage(context, tr('Проверьте поля формы'), type: MessageType.error);
      return;
    }
    setState(() => _saving = true);
    final title = _type == 'Другое' ? _custom.text.trim() : _type!;
    try {
      // a newly picked photo is copied to the app folder; the picker's file is
      // only a cache
      final photo = _photoChanged && _photo != null
          ? await AppPaths.storePhoto(
              File(_photo!),
              AppPaths.reactionPhotosDir,
              prefix: 'reaction',
            )
          : _photo;
      if (!mounted) return;
      await context.read<SafetyProvider>().saveReaction(
        id: widget.reactionId,
        productId: _productId!,
        title: title,
        severity: _severity,
        date: _date,
        notes: _notes.text,
        photoPath: photo,
      );
      if (!mounted) return;
      showMessage(
        context,
        _editing ? tr('Запись обновлена') : tr('Реакция добавлена в дневник'),
        type: MessageType.success,
      );
      Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        showMessage(
          context,
          tr('Не удалось сохранить запись'),
          type: MessageType.error,
        );
      }
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: tr('Удалить запись?'),
      message: tr('Запись будет удалена из дневника реакций.'),
      confirmLabel: tr('Удалить'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    final safety = context.read<SafetyProvider>();
    final r = await safety.reactionById(widget.reactionId!);
    if (r != null) await safety.deleteReaction(r);
    if (!mounted) return;
    showMessage(context, tr('Запись удалена'), type: MessageType.success);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final products = context.watch<CatalogProvider>().products;
    final pal = context.pal;

    return PageScaffold(
      title: _editing ? tr('Редактировать реакцию') : tr('Добавить реакцию'),
      showNav: false,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  _label(tr('Продукт')),
                  DropdownButtonFormField<int>(
                    initialValue: products.any((p) => p.id == _productId)
                        ? _productId
                        : null,
                    isExpanded: true,
                    hint: Text(tr('Выберите продукт')),
                    validator: (v) => v == null ? tr('Выберите продукт') : null,
                    items: [
                      for (final p in products)
                        DropdownMenuItem(
                          value: p.id,
                          child: Text(
                            '${p.brand} — ${tr(p.name)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _productId = v),
                  ),
                  const SizedBox(height: 14),
                  _label(tr('Тип реакции')),
                  DropdownButtonFormField<String>(
                    initialValue: _type,
                    isExpanded: true,
                    hint: Text(tr('Выберите реакцию')),
                    validator: (v) =>
                        v == null ? tr('Выберите тип реакции') : null,
                    items: [
                      for (final t in AppConstants.reactionTypes)
                        DropdownMenuItem(value: t, child: Text(tr(t))),
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
                        field: tr('Описание'),
                      ),
                      decoration: InputDecoration(
                        hintText: tr('Опишите реакцию'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _label(
                    trf('Тяжесть: {_severity} из 5', {'_severity': _severity}),
                  ),
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
                  _label(tr('Дата')),
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
                  _label(tr('Заметка (необязательно)')),
                  TextFormField(
                    controller: _notes,
                    maxLines: 3,
                    maxLength: 300,
                    validator: (v) => (v ?? '').length > 300
                        ? tr('Максимум 300 символов')
                        : null,
                    decoration: InputDecoration(
                      hintText: tr('Что вы почувствовали?'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _label(tr('Фото (необязательно)')),
                  _photoSection(),
                  const SizedBox(height: 4),
                  Text(
                    tr(
                      'Фото хранится только на этом телефоне и никуда не отправляется.',
                    ),
                    style: AppTextStyles.caption.copyWith(color: pal.subtext),
                  ),
                  const SizedBox(height: 16),
                  CustomButton(
                    label: _editing
                        ? tr('Сохранить изменения')
                        : tr('Добавить в дневник'),
                    loading: _saving,
                    onPressed: _save,
                  ),
                  if (_editing) ...[
                    const SizedBox(height: 10),
                    CustomButton(
                      label: tr('Удалить запись'),
                      outlined: true,
                      color: AppColors.sale,
                      onPressed: _delete,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      tr('История изменений'),
                      style: AppTextStyles.subtitle,
                    ),
                    const SizedBox(height: 8),
                    ReactionHistoryList(changes: _history),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _photoSection() {
    final path = _photo;
    final exists = path != null && File(path).existsSync();
    if (!exists) {
      return CustomButton(
        label: tr('Добавить фото'),
        icon: Icons.add_a_photo_outlined,
        outlined: true,
        onPressed: _pickPhoto,
      );
    }
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            File(path),
            width: 90,
            height: 90,
            fit: BoxFit.cover,
            cacheWidth: 300,
            errorBuilder: (_, _, _) => const SizedBox(width: 90, height: 90),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            children: [
              CustomButton(
                label: tr('Заменить фото'),
                outlined: true,
                onPressed: _pickPhoto,
              ),
              const SizedBox(height: 8),
              CustomButton(
                label: tr('Убрать фото'),
                outlined: true,
                color: AppColors.sale,
                onPressed: () => setState(() {
                  _photo = null;
                  _photoChanged = false;
                }),
              ),
            ],
          ),
        ),
      ],
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
