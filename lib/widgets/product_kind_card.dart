import 'package:flutter/material.dart';

import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/services/catalog/product_classifier.dart' as v2;
import 'package:cosmetix/services/ingredient_catalog.dart';
import 'package:cosmetix/widgets/app_card.dart';

/// What a product IS (form), whether it is washed off, what it is for and which
/// active ingredient groups stand high in its INCI list: the classifier v2, shown
/// separately instead of one shop-style category.
///
/// The classification is automatic (name + category + INCI). It never states a
/// concentration: the INCI position only says that an ingredient is not a trace.
class ProductKindCard extends StatelessWidget {
  const ProductKindCard({super.key, required this.product});

  final Product product;

  static const _classifier = v2.ProductClassifier();

  static v2.ProductClass classify(Product p) => _classifier.classify(
    name: p.name,
    category: p.category,
    inci: p.inci,
    zone: p.zone,
  );

  static String formLabel(v2.ProductForm f) => switch (f) {
    v2.ProductForm.cream => tr('Крем'),
    v2.ProductForm.gel => tr('Гель'),
    v2.ProductForm.serum => tr('Сыворотка'),
    v2.ProductForm.toner => tr('Тонер'),
    v2.ProductForm.essence => tr('Эссенция'),
    v2.ProductForm.ampoule => tr('Ампула'),
    v2.ProductForm.lotion => tr('Лосьон / эмульсия'),
    v2.ProductForm.cleanser => tr('Очищающее средство'),
    v2.ProductForm.micellar => tr('Мицеллярная вода'),
    v2.ProductForm.cleansingOil => tr('Очищающее масло'),
    v2.ProductForm.mask => tr('Маска'),
    v2.ProductForm.sunscreen => tr('Солнцезащитное средство'),
    v2.ProductForm.peeling => tr('Пилинг / эксфолиант'),
    v2.ProductForm.lipCare => tr('Уход за губами'),
    v2.ProductForm.shampoo => tr('Шампунь'),
    v2.ProductForm.makeup => tr('Макияж'),
    v2.ProductForm.perfume => tr('Парфюмерия'),
    v2.ProductForm.giftSet => tr('Набор'),
  };

  static String purposeLabel(v2.Purpose p) => switch (p) {
    v2.Purpose.cleansing => tr('Очищение'),
    v2.Purpose.hydration => tr('Увлажнение'),
    v2.Purpose.barrierRepair => tr('Восстановление барьера'),
    v2.Purpose.acneCare => tr('Уход при акне'),
    v2.Purpose.exfoliation => tr('Отшелушивание'),
    v2.Purpose.sunProtection => tr('Защита от солнца'),
    v2.Purpose.rednessCare => tr('Уход при покраснении'),
    v2.Purpose.brightening => tr('Выравнивание тона'),
    v2.Purpose.soothing => tr('Успокоение'),
    v2.Purpose.oilControl => tr('Контроль жирности'),
  };

  /// Russian source label of an active group (translated by the caller).
  static String? activeLabel(String code) {
    for (final g in IngredientCatalog.groups) {
      if (g.code == code) return tr(g.label);
    }
    return null;
  }

  /// Makeup, perfume and gift sets have no skincare purpose to explain; a
  /// product the rules cannot place is shown with a "waiting for review" note.
  static bool applies(Product p) {
    final c = classify(p);
    final f = c.form;
    final skincare =
        f != null &&
        f != v2.ProductForm.makeup &&
        f != v2.ProductForm.perfume &&
        f != v2.ProductForm.giftSet;
    return skincare || c.needsReview;
  }

  @override
  Widget build(BuildContext context) {
    final c = classify(product);
    final pal = context.pal;
    final form = c.form;
    if (!applies(product)) return const SizedBox.shrink();
    final actives = [
      for (final h in c.actives)
        if (h.rank <= v2.ProductClassifier.meaningfulRank)
          if (activeLabel(h.code) != null) activeLabel(h.code)!,
    ];
    Widget row(String k, String v) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$k: ',
              style: AppTextStyles.small.copyWith(color: pal.subtext),
            ),
            TextSpan(text: v, style: AppTextStyles.small),
          ],
        ),
      ),
    );
    return AppCard(
      key: const Key('product-kind-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (form != null) row(tr('Тип'), formLabel(form)),
          if (c.rinseOff != null)
            row(
              tr('Применение'),
              c.rinseOff! ? tr('смывается') : tr('остаётся на коже'),
            ),
          if (c.purposes.isNotEmpty)
            row(tr('Назначение'), c.purposes.map(purposeLabel).join(', ')),
          if (actives.isNotEmpty)
            row(tr('В начале состава'), actives.join(', ')),
          if (c.needsReview)
            Text(
              tr('Тип или назначение не подтверждены: ждёт проверки специалистом.'),
              key: const Key('product-kind-review'),
              style: AppTextStyles.caption.copyWith(color: AppColors.warning),
            ),
          Text(
            tr(
              'Определено автоматически по названию и составу; это не описание производителя.',
            ),
            style: AppTextStyles.caption.copyWith(color: pal.subtext),
          ),
        ],
      ),
    );
  }
}
