import 'package:cosmetix/core/i18n/tr.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/formatters.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/core/utils/validators.dart';
import 'package:cosmetix/models/social_models.dart';
import 'package:cosmetix/providers/auth_provider.dart';
import 'package:cosmetix/providers/reviews_provider.dart';
import 'package:cosmetix/repositories/review_repository.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/common_widgets.dart';
import 'package:cosmetix/widgets/custom_button.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';

class ReviewsScreen extends StatelessWidget {
  const ReviewsScreen({super.key, required this.productId});

  final int productId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (c) =>
          ReviewsProvider(c.read<ReviewRepository>(), productId)..load(),
      child: _ReviewsBody(productId: productId),
    );
  }
}

class _ReviewsBody extends StatefulWidget {
  const _ReviewsBody({required this.productId});

  final int productId;

  @override
  State<_ReviewsBody> createState() => _ReviewsBodyState();
}

class _ReviewsBodyState extends State<_ReviewsBody> {
  final _formKey = GlobalKey<FormState>();
  final _text = TextEditingController();
  int _rating = 0;
  bool _ratingError = false;
  bool _showAll = false;
  bool _saving = false;
  Review? _editing;

  /// Photo chosen in the form (temporary picker path until the review is saved).
  String? _photo;
  bool _photoChanged = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
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
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1280,
        imageQuality: 85,
      );
      if (file != null && mounted) {
        setState(() {
          _photo = file.path;
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

  void _resetForm() {
    _editing = null;
    _rating = 0;
    _photo = null;
    _photoChanged = false;
    _text.clear();
  }

  Future<void> _submit() async {
    final valid = _formKey.currentState!.validate();
    setState(() => _ratingError = _rating == 0);
    if (!valid || _rating == 0) {
      if (_rating == 0) {
        showMessage(
          context,
          tr('Поставьте оценку товару'),
          type: MessageType.warning,
        );
      }
      return;
    }
    setState(() => _saving = true);
    final reviews = context.read<ReviewsProvider>();
    final auth = context.read<AuthProvider>();
    try {
      // copy a newly picked photo next to the database; keep the old one otherwise
      final saved = _photoChanged && _photo != null
          ? await reviews.savePhoto(_photo!)
          : _photo;
      if (_editing != null) {
        await reviews.edit(_editing!, _rating, _text.text, photoPath: saved);
      } else {
        await reviews.add(
          userId: auth.userId,
          author: auth.user!.firstName,
          rating: _rating,
          body: _text.text,
          photoPath: saved,
        );
      }
      if (!mounted) return;
      showMessage(
        context,
        _editing != null
            ? tr('Отзыв обновлён')
            : tr('Спасибо! Отзыв опубликован'),
        type: MessageType.success,
      );
      setState(_resetForm);
    } catch (_) {
      if (mounted) {
        showMessage(
          context,
          tr('Не удалось сохранить отзыв'),
          type: MessageType.error,
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  void _openPhoto(Review r) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: InteractiveViewer(
          child: Image.file(File(r.photoPath!), fit: BoxFit.contain),
        ),
      ),
    );
  }

  Future<void> _delete(Review r) async {
    final ok = await confirmDialog(
      context,
      title: tr('Удалить отзыв?'),
      message: tr('Это действие нельзя отменить.'),
      confirmLabel: tr('Удалить'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    await context.read<ReviewsProvider>().delete(r);
    if (mounted) {
      showMessage(context, tr('Отзыв удалён'), type: MessageType.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ReviewsProvider>();
    final myId = context.read<AuthProvider>().user?.id;
    final pal = context.pal;
    final list = _showAll
        ? provider.reviews
        : provider.reviews.take(3).toList();
    final withPhoto = [
      for (final r in provider.reviews)
        if (r.photoPath != null && File(r.photoPath!).existsSync()) r,
    ];

    return PageScaffold(
      title: tr('Отзывы'),
      centerTitle: true,
      child: provider.loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                SectionTitle(
                  tr('Фото товара от покупателей'),
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  trailing: Text(
                    trf('{v0} фото', {'v0': withPhoto.length}),
                    style: AppTextStyles.small.copyWith(
                      color: context.pal.accent,
                    ),
                  ),
                ),
                if (withPhoto.isEmpty)
                  Text(
                    tr('Пока никто не добавил фото. Будьте первым!'),
                    style: AppTextStyles.small.copyWith(color: pal.subtext),
                  )
                else
                  SizedBox(
                    height: 84,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: withPhoto.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => SizedBox(
                        width: 64,
                        child: Column(
                          children: [
                            SizedBox(
                              height: 56,
                              child: _ReviewPhoto(
                                path: withPhoto[i].photoPath!,
                                radius: 12,
                                onTap: () => _openPhoto(withPhoto[i]),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              tr(withPhoto[i].author),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.caption,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                AppCard(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _editing != null
                                    ? tr('Редактировать отзыв')
                                    : tr('Оставьте свой отзыв'),
                                style: AppTextStyles.subtitle,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primarySoft,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                trf('{v0} {v1}', {
                                  'v0': provider.reviews.length,
                                  'v1': Formatters.plural(
                                    provider.reviews.length,
                                    'отзыв',
                                    'отзыва',
                                    'отзывов',
                                  ),
                                }),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: context.pal.accent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          tr('Оцените товар'),
                          style: AppTextStyles.small.copyWith(
                            color: pal.subtext,
                          ),
                        ),
                        const SizedBox(height: 6),
                        StarPicker(
                          value: _rating,
                          onChanged: (v) => setState(() {
                            _rating = v;
                            _ratingError = false;
                          }),
                        ),
                        if (_ratingError)
                          Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                              tr('Выберите оценку'),
                              style: TextStyle(
                                color: AppColors.danger,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _text,
                          maxLines: 3,
                          maxLength: 500,
                          validator: (v) => Validators.text(
                            v,
                            min: 10,
                            max: 500,
                            field: tr('Отзыв'),
                          ),
                          decoration: InputDecoration(
                            hintText: tr('Расскажите, как вам товар...'),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (_photo != null && File(_photo!).existsSync())
                              Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: SizedBox(
                                  width: 64,
                                  height: 64,
                                  child: _ReviewPhoto(
                                    path: _photo!,
                                    radius: 12,
                                  ),
                                ),
                              ),
                            Expanded(
                              child: Wrap(
                                spacing: 8,
                                children: [
                                  TextButton.icon(
                                    onPressed: _pickPhoto,
                                    icon: const Icon(
                                      Icons.add_a_photo_outlined,
                                      size: 20,
                                    ),
                                    label: Text(
                                      _photo == null
                                          ? tr('Добавить фото товара')
                                          : tr('Заменить фото'),
                                    ),
                                  ),
                                  if (_photo != null)
                                    TextButton(
                                      onPressed: () => setState(() {
                                        _photo = null;
                                        _photoChanged = false;
                                      }),
                                      child: Text(tr('Убрать')),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (_editing != null) ...[
                              Expanded(
                                child: CustomButton(
                                  label: tr('Отмена'),
                                  outlined: true,
                                  onPressed: () => setState(_resetForm),
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Expanded(
                              child: CustomButton(
                                label: _editing != null
                                    ? tr('Сохранить')
                                    : tr('Отправить отзыв'),
                                loading: _saving,
                                onPressed: _submit,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SectionTitle(
                  tr('Последние отзывы'),
                  trailing: provider.reviews.length > 3
                      ? LinkText(
                          _showAll ? tr('Свернуть') : tr('Все'),
                          onTap: () => setState(() => _showAll = !_showAll),
                        )
                      : null,
                ),
                if (provider.reviews.isEmpty)
                  EmptyState(
                    icon: Icons.rate_review_outlined,
                    title: tr('Отзывов пока нет'),
                    subtitle: tr('Оставьте первый отзыв об этом товаре'),
                  ),
                for (final r in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(tr(r.author), style: AppTextStyles.bodyBold),
                              const Spacer(),
                              Text(
                                Formatters.ago(r.createdAt),
                                style: AppTextStyles.caption.copyWith(
                                  color: pal.subtext,
                                ),
                              ),
                              if (r.userId != null && r.userId == myId)
                                PopupMenuButton<String>(
                                  tooltip: tr('Действия'),
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(Icons.more_vert, size: 18),
                                  onSelected: (v) {
                                    if (v == 'edit') {
                                      setState(() {
                                        _editing = r;
                                        _rating = r.rating;
                                        _text.text = r.body;
                                        _photo = r.photoPath;
                                        _photoChanged = false;
                                      });
                                    } else {
                                      _delete(r);
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text(tr('Редактировать')),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text(tr('Удалить')),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          StarRow(value: r.rating, size: 14),
                          const SizedBox(height: 4),
                          Text(tr(r.body), style: AppTextStyles.small),
                          if (r.photoPath != null &&
                              File(r.photoPath!).existsSync())
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: SizedBox(
                                width: 120,
                                height: 120,
                                child: _ReviewPhoto(
                                  path: r.photoPath!,
                                  radius: 12,
                                  onTap: () => _openPhoto(r),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ReviewPhoto extends StatelessWidget {
  const _ReviewPhoto({required this.path, required this.radius, this.onTap});

  final String path;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.file(
          File(path),
          fit: BoxFit.cover,
          cacheWidth: 360,
          errorBuilder: (_, _, _) =>
              const ColoredBox(color: AppColors.primarySoft),
        ),
      ),
    );
  }
}
