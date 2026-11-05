import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/common_widgets.dart';
import 'package:cosmetix/widgets/pill_segments.dart';
import 'package:flutter/material.dart';

import '../catalog/try_on_item.dart';
import '../domain/makeup_look.dart';
import 'makeup_palettes.dart';
import 'virtual_makeup_controller.dart';

/// "Catalog / Own colour": the two ways to choose a colour.
class ColourModeBar extends StatelessWidget {
  const ColourModeBar({super.key, required this.controller});

  final VirtualMakeupController controller;

  @override
  Widget build(BuildContext context) {
    return PillSegments<ColourMode>(
      key: const Key('vm-colour-mode'),
      segments: [
        PillSegment(
          value: ColourMode.catalog,
          icon: Icons.storefront_outlined,
          label: tr('Каталог'),
        ),
        PillSegment(
          value: ColourMode.manual,
          icon: Icons.palette_outlined,
          label: tr('Свой цвет'),
        ),
      ],
      selected: controller.colourMode,
      onChanged: (v) => v == ColourMode.catalog
          ? controller.useCatalogColours()
          : controller.useManualColours(),
    );
  }
}

/// What the colour of a product is worth, in words.
String trustText(TryOnItem i) => switch (i.status) {
  'manufacturer' => tr('Цвет по данным производителя'),
  'swatch_sampled' => tr(
    'Цвет измерен по образцу производителя, приблизительно',
  ),
  _ => tr('Цвет оценён по фото товара, не по данным производителя'),
};

/// The products of the catalog chosen for the face, their other shades and
/// similar products. The colour is always called approximate.
class CatalogPanel extends StatelessWidget {
  const CatalogPanel({
    super.key,
    required this.controller,
    required this.onOpenProduct,
  });

  final VirtualMakeupController controller;

  /// Opens the product page (cart, favourites): the app decides how.
  final ValueChanged<int>? onOpenProduct;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final pal = context.pal;
    final current = c.current;
    return Column(
      key: const Key('vm-catalog-panel'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final z in MakeupZone.values)
          if (c.items[z] != null) ...[
            SelectedItemCard(
              item: c.items[z]!,
              look: c.look.of(z),
              onIntensity: (v) =>
                  c.setZone(z, c.look.of(z).copyWith(intensity: v)),
              onRemove: () => c.clearItem(z),
              onOpen: onOpenProduct == null
                  ? null
                  : () => onOpenProduct!(c.items[z]!.productId),
            ),
            const SizedBox(height: 8),
          ],
        Text(
          tr(
            'Цвет оттенка приблизительный: он зависит от освещения на фото, экрана и свойств косметики. Реальный продукт может выглядеть иначе.',
          ),
          key: const Key('vm-colour-caveat'),
          style: AppTextStyles.caption.copyWith(color: pal.subtext),
        ),
        const SizedBox(height: 12),
        if (current != null && c.lineShades.isNotEmpty) ...[
          Text(
            tr(
              current.panKey != null
                  ? 'Цвета палетки'
                  : 'Другие оттенки линейки',
            ),
            style: AppTextStyles.bodyBold,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 78,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final s in c.lineShades)
                  ShadeChip(
                    key: s.panKey != null
                        ? Key('vm-pan-${s.panKey}')
                        : Key('vm-shade-${s.productId}'),
                    item: s,
                    selected: s == current,
                    onTap: () => c.applyItem(s),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text(tr('Подбор по виду макияжа'), style: AppTextStyles.bodyBold),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final z in MakeupZone.values)
              AppChip(
                key: Key('vm-kind-${z.name}'),
                label: tr(MakeupPalettes.zoneName(z)),
                selected: c.browseKind == z,
                onTap: () => c.loadBrowse(z),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (c.browseList.isEmpty)
          Text(
            tr(
              'Для этого вида в каталоге пока нет товаров с известным цветом. Выберите «Свой цвет».',
            ),
            key: const Key('vm-no-products'),
            style: AppTextStyles.small.copyWith(color: pal.subtext),
          )
        else
          for (final p in c.browseList)
            ProductTile(
              key: Key('vm-product-${p.productId}'),
              item: p,
              selected: c.items[p.kind] == p,
              onTap: () => c.applyItem(p),
            ),
      ],
    );
  }
}

/// A product (shade) chosen for a zone: who it is, how sure the colour is, how
/// strong it is applied, and the way back to its page.
class SelectedItemCard extends StatelessWidget {
  const SelectedItemCard({
    super.key,
    required this.item,
    required this.look,
    required this.onIntensity,
    required this.onRemove,
    required this.onOpen,
  });

  final TryOnItem item;
  final ZoneLook look;
  final ValueChanged<double> onIntensity;
  final VoidCallback onRemove;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final shade = item.shadeLabel;
    return AppCard(
      key: Key('vm-selected-${item.kind.name}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Photo(path: item.photo),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(MakeupPalettes.zoneName(item.kind)),
                      style: AppTextStyles.caption.copyWith(color: pal.subtext),
                    ),
                    Text(item.brand, style: AppTextStyles.small),
                    Text(
                      item.lineName,
                      key: Key('vm-item-name-${item.kind.name}'),
                      style: AppTextStyles.bodyBold,
                    ),
                    if (shade != null)
                      Text(
                        trf('Оттенок: {v0}', {'v0': shade}),
                        key: Key('vm-item-shade-${item.kind.name}'),
                        style: AppTextStyles.small,
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _Swatch(color: item.colour!, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            trustText(item),
                            key: Key('vm-item-trust-${item.kind.name}'),
                            style: AppTextStyles.caption.copyWith(
                              color: item.isApproximate
                                  ? AppColors.warning
                                  : pal.subtext,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (item.cellLabel != null)
                      Text(
                        item.cellLabel!,
                        key: Key('vm-item-cell-${item.kind.name}'),
                        style: AppTextStyles.small,
                      ),
                    if (item.finish != null)
                      Text(
                        trf('Покрытие: {v0}', {
                          'v0': tr(_finish(item.finish!)),
                        }),
                        style: AppTextStyles.caption.copyWith(
                          color: pal.subtext,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                key: Key('vm-remove-${item.kind.name}'),
                tooltip: tr('Убрать'),
                onPressed: onRemove,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Text(
            trf('Интенсивность: {v0}%', {'v0': (look.intensity * 100).round()}),
            style: AppTextStyles.small.copyWith(color: pal.subtext),
          ),
          Slider(
            key: Key('vm-item-slider-${item.kind.name}'),
            value: look.intensity,
            onChanged: onIntensity,
          ),
          if (onOpen != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: Key('vm-open-product-${item.productId}'),
                onPressed: onOpen,
                icon: const Icon(Icons.shopping_bag_outlined),
                label: Text(tr('К карточке товара')),
              ),
            ),
        ],
      ),
    );
  }

  static String _finish(String f) => switch (f) {
    'matte' => 'матовое',
    'satin' => 'сатиновое',
    'gloss' => 'глянцевое',
    _ => 'с шиммером',
  };
}

/// One shade of a line: a colour circle and its code.
class ShadeChip extends StatelessWidget {
  const ShadeChip({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final TryOnItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 64,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? pal.accent : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: _Swatch(color: item.colour!, size: 38),
              ),
              const SizedBox(height: 2),
              Text(
                item.panPosition?.toString() ??
                    item.shadeCode ??
                    item.shadeName ??
                    '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A product in the list of a kind.
class ProductTile extends StatelessWidget {
  const ProductTile({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final TryOnItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final shade = item.shadeLabel;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? pal.accent : pal.border),
        ),
        leading: _Swatch(color: item.colour!, size: 32),
        title: Text(
          '${item.brand} · ${item.name}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.small,
        ),
        subtitle: shade == null
            ? null
            : Text(shade, style: AppTextStyles.caption),
        trailing: selected ? Icon(Icons.check_circle, color: pal.accent) : null,
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.black12),
    ),
  );
}

/// The PACKAGE photo of a product (not a picture of the shade).
class _Photo extends StatelessWidget {
  const _Photo({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final p = path;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 56,
        height: 56,
        child: p == null
            ? ColoredBox(color: context.pal.field)
            : Image.asset(
                p,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => ColoredBox(color: context.pal.field),
              ),
      ),
    );
  }
}
