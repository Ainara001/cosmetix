import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/database/catalog_structure_data.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/models/palette_models.dart';
import 'package:cosmetix/repositories/catalog_structure_repository.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/widgets/shade_widgets.dart';

/// The part of a product page that belongs to a PALETTE: the variant of the
/// line (00, 01, 02 ...), the cells inside the chosen variant and, behind one
/// quiet link, what is known about where those facts come from.
///
/// One palette is one product: price, cart and favourite stay with the product
/// page. Nothing is shown for a product that is not a palette. Reads the local
/// database only.
class PaletteSection extends StatefulWidget {
  const PaletteSection({super.key, required this.productId});

  final int productId;

  @override
  State<PaletteSection> createState() => _PaletteSectionState();
}

class _Data {
  const _Data(this.info, this.variants);
  final VariantInfo info;
  final List<LineVariant> variants;
}

class _PaletteSectionState extends State<PaletteSection> {
  Future<_Data?>? _data;

  Future<_Data?> _load() async {
    final repo = CatalogStructureRepository(context.read<DatabaseHelper>());
    final info = await repo.variant(widget.productId);
    if (info == null || !info.isPalette) return null;
    final key = info.line?.key;
    final variants = key == null
        ? const <LineVariant>[]
        : await repo.variantsOfLine(key);
    return _Data(info, variants);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  @override
  void didUpdateWidget(PaletteSection old) {
    super.didUpdateWidget(old);
    if (old.productId != widget.productId) _data = _load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Data?>(
      future: _data,
      builder: (context, snap) {
        final d = snap.data;
        if (d == null) return const SizedBox.shrink();
        final info = d.info;
        final pans = info.pans;
        return Column(
          key: const Key('palette-section'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 14),
            Text(
              trf('Вариант палетки: {v}', {
                'v': [
                  if (info.shadeCode != null) info.shadeCode!,
                  if (info.shadeName != null) info.shadeName!,
                ].join(' '),
              }),
              key: const Key('palette-variant-title'),
              style: AppTextStyles.bodyBold,
            ),
            if (d.variants.length > 1) ...[
              const SizedBox(height: 8),
              VariantChips(
                variants: d.variants,
                selectedId: widget.productId,
                onSelect: (v) {
                  if (v.productId == widget.productId) return;
                  // the same page for another variant, not one more page on top
                  Navigator.pushReplacementNamed(
                    context,
                    AppRoutes.product,
                    arguments: v.productId,
                  );
                },
              ),
            ],
            const SizedBox(height: 16),
            if (pans.isNotEmpty) ...[
              Text(
                trf('Цвета внутри палетки: {n}', {'n': pans.length}),
                style: AppTextStyles.bodyBold,
              ),
              const SizedBox(height: 10),
              PanGrid(pans: pans),
              const SizedBox(height: 12),
              ApproxNote(
                key: const Key('palette-cells-note'),
                text: info.tryablePans.isEmpty
                    ? tr(
                        'Цвета ячеек ещё не измерены, поэтому они показаны серыми. Примерка палетки станет доступна после измерения.',
                      )
                    : ApproxNote.standard,
              ),
            ] else
              ApproxNote(
                key: const Key('palette-cells-unknown'),
                text: tr(
                  'Число цветов в этой палетке не подтверждено, поэтому мы его не показываем.',
                ),
              ),
            const SizedBox(height: 4),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: const Key('palette-data-link'),
                onPressed: () => showPaletteData(context, info),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 0),
                  minimumSize: const Size(48, 40),
                  foregroundColor: context.pal.accent,
                ),
                child: Text(tr('О данных')),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// What the confidence value means, in words a shopper understands.
String confidenceText(String? c) => switch (c) {
  FactConfidence.officialPage => tr(
    'Страница производителя, проверено вручную',
  ),
  FactConfidence.officialPageUnchecked => tr(
    'Страница производителя, ещё не проверено вручную',
  ),
  FactConfidence.thirdParty => tr('Сторонний источник (каталог, продавец)'),
  FactConfidence.unconfirmed => tr('Не подтверждено'),
  _ => tr('Не указано'),
};

/// The sheet behind "О данных": the facts and where they come from.
Future<void> showPaletteData(BuildContext context, VariantInfo info) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.pal.surface,
    builder: (context) {
      final pal = context.pal;
      Widget row(String label, String? value) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTextStyles.caption.copyWith(color: pal.subtext),
            ),
            const SizedBox(height: 2),
            Text(value ?? tr('Не указано'), style: AppTextStyles.body),
          ],
        ),
      );
      final line = info.line;
      final count = info.panCount;
      return SafeArea(
        child: SingleChildScrollView(
          key: const Key('palette-data-sheet'),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('О данных'), style: AppTextStyles.title),
              const SizedBox(height: 14),
              row(tr('Бренд'), line?.brand),
              row(tr('Линейка'), line?.name),
              row(
                tr('Вариант'),
                [
                  if (info.shadeCode != null) info.shadeCode!,
                  if (info.shadeName != null) info.shadeName!,
                ].join(' '),
              ),
              row(
                tr('Цветов в палетке'),
                count == null ? tr('Не подтверждено') : '$count',
              ),
              row(tr('Достоверность'), confidenceText(info.factsConfidence)),
              row(tr('Источник'), info.factsSource),
              row(
                tr('Проверено'),
                info.factsCheckedAt ?? tr('Дата проверки не записана'),
              ),
              const SizedBox(height: 2),
              ApproxNote(
                compact: true,
                text: tr(
                  'Цвета ячеек не берутся с упаковки или фото и не копируются с сайтов брендов: они появятся здесь только после нашего собственного измерения образцов.',
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
