import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/formatters.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/core/utils/validators.dart';
import 'package:cosmetix/models/social_models.dart';
import 'package:cosmetix/providers/auth_provider.dart';
import 'package:cosmetix/providers/catalog_provider.dart';
import 'package:cosmetix/providers/reviews_provider.dart';
import 'package:cosmetix/repositories/review_repository.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/common_widgets.dart';
import 'package:cosmetix/widgets/custom_button.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';
import 'package:cosmetix/widgets/product_art.dart';

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

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final valid = _formKey.currentState!.validate();
    setState(() => _ratingError = _rating == 0);
    if (!valid || _rating == 0) {
      if (_rating == 0) {
        showMessage(
          context,
          'Поставьте оценку товару',
          type: MessageType.warning,
        );
      }
      return;
    }
    setState(() => _saving = true);
    final reviews = context.read<ReviewsProvider>();
    final auth = context.read<AuthProvider>();
    try {
      if (_editing != null) {
        await reviews.edit(_editing!, _rating, _text.text);
      } else {
        await reviews.add(
          userId: auth.userId,
          author: auth.user!.firstName,
          rating: _rating,
          body: _text.text,
        );
      }
      if (!mounted) return;
      showMessage(
        context,
        _editing != null ? 'Отзыв обновлён' : 'Спасибо! Отзыв опубликован',
        type: MessageType.success,
      );
      setState(() {
        _editing = null;
        _rating = 0;
        _text.clear();
      });
    } catch (_) {
      if (mounted) {
        showMessage(
          context,
          'Не удалось сохранить отзыв',
          type: MessageType.error,
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _delete(Review r) async {
    final ok = await confirmDialog(
      context,
      title: 'Удалить отзыв?',
      message: 'Это действие нельзя отменить.',
      confirmLabel: 'Удалить',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await context.read<ReviewsProvider>().delete(r);
    if (mounted) {
      showMessage(context, 'Отзыв удалён', type: MessageType.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ReviewsProvider>();
    final product = context.watch<CatalogProvider>().byId(widget.productId);
    final myId = context.read<AuthProvider>().user?.id;
    final pal = context.pal;
    final list = _showAll
        ? provider.reviews
        : provider.reviews.take(3).toList();

    return PageScaffold(
      title: 'Отзывы',
      centerTitle: true,
      child: provider.loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                SectionTitle(
                  'Фото товара от покупателей',
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  trailing: Text(
                    '${provider.reviews.length} фото',
                    style: AppTextStyles.small.copyWith(
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
                if (product != null && provider.reviews.isNotEmpty)
                  SizedBox(
                    height: 84,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: provider.reviews.length.clamp(0, 8),
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => SizedBox(
                        width: 64,
                        child: Column(
                          children: [
                            SizedBox(
                              height: 56,
                              child: ProductArt(
                                art: product.art,
                                color: product.color,
                                radius: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              provider.reviews[i].author,
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
                                    ? 'Редактировать отзыв'
                                    : 'Оставьте свой отзыв',
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
                                '${provider.reviews.length} ${Formatters.plural(provider.reviews.length, 'отзыв', 'отзыва', 'отзывов')}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Оцените товар',
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
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                              'Выберите оценку',
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
                            field: 'Отзыв',
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Расскажите, как вам товар...',
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (_editing != null) ...[
                              Expanded(
                                child: CustomButton(
                                  label: 'Отмена',
                                  outlined: true,
                                  onPressed: () => setState(() {
                                    _editing = null;
                                    _rating = 0;
                                    _text.clear();
                                  }),
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Expanded(
                              child: CustomButton(
                                label: _editing != null
                                    ? 'Сохранить'
                                    : 'Отправить отзыв',
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
                  'Последние отзывы',
                  trailing: provider.reviews.length > 3
                      ? LinkText(
                          _showAll ? 'Свернуть' : 'Все',
                          onTap: () => setState(() => _showAll = !_showAll),
                        )
                      : null,
                ),
                if (provider.reviews.isEmpty)
                  const EmptyState(
                    icon: Icons.rate_review_outlined,
                    title: 'Отзывов пока нет',
                    subtitle: 'Оставьте первый отзыв об этом товаре',
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
                              Text(r.author, style: AppTextStyles.bodyBold),
                              const Spacer(),
                              Text(
                                Formatters.ago(r.createdAt),
                                style: AppTextStyles.caption.copyWith(
                                  color: pal.subtext,
                                ),
                              ),
                              if (r.userId != null && r.userId == myId)
                                PopupMenuButton<String>(
                                  tooltip: 'Действия',
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(Icons.more_vert, size: 18),
                                  onSelected: (v) {
                                    if (v == 'edit') {
                                      setState(() {
                                        _editing = r;
                                        _rating = r.rating;
                                        _text.text = r.body;
                                      });
                                    } else {
                                      _delete(r);
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Редактировать'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Удалить'),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          StarRow(value: r.rating, size: 14),
                          const SizedBox(height: 4),
                          Text(r.body, style: AppTextStyles.small),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
