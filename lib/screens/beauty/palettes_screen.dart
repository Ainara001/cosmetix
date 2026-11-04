import 'package:flutter/material.dart';

import 'package:cosmetix/core/beauty/beauty_codes.dart';
import 'package:cosmetix/core/beauty/color_palettes.dart';
import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/screens/beauty/color_result_screen.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/common_widgets.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';

/// Full palettes of all four colour types: what suits each one (lips, blush,
/// eyes, clothes, metal) and what to avoid. The user's own type is first.
class PalettesScreen extends StatefulWidget {
  const PalettesScreen({super.key, this.highlight});

  /// The user's colour type (opened first), if the Beauty Test is done.
  final ColorType? highlight;

  @override
  State<PalettesScreen> createState() => _PalettesScreenState();
}

class _PalettesScreenState extends State<PalettesScreen> {
  late ColorType _type = widget.highlight ?? ColorType.spring;

  static const _hint = {
    ColorType.spring: 'Светлый, тёплый, чистый',
    ColorType.summer: 'Светлый, холодный, мягкий',
    ColorType.autumn: 'Глубокий, тёплый, мягкий',
    ColorType.winter: 'Глубокий, холодный, контрастный',
  };

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final palette = ColorPalettes.seasons[_type]!;
    return PageScaffold(
      title: tr('Палитры цветотипов'),
      bigTitle: true,
      showNav: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final t in ColorType.values) ...[
                  AppChip(
                    label: t == widget.highlight
                        ? '${tr(t.label)} ★'
                        : tr(t.label),
                    selected: _type == t,
                    onTap: () => setState(() => _type = t),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            color: context.pal.pinkSoft,
            borderColor: Colors.transparent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(_type.label), style: AppTextStyles.h2),
                const SizedBox(height: 2),
                Text(
                  tr(_hint[_type]!),
                  style: AppTextStyles.small.copyWith(color: pal.subtext),
                ),
                if (_type == widget.highlight)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      tr('Это ваш цветотип'),
                      style: AppTextStyles.small.copyWith(
                        color: context.pal.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          PaletteBlocks(palette: palette),
        ],
      ),
    );
  }
}
