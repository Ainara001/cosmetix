import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:cosmetix/core/beauty/beauty_codes.dart';
import 'package:cosmetix/core/beauty/color_palettes.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/routes/route_args.dart';
import 'package:cosmetix/services/color_test_service.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/custom_button.dart';
import 'package:cosmetix/models/recommendation.dart';
import 'package:cosmetix/providers/catalog_provider.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';
import 'package:cosmetix/widgets/product_mini_card.dart';
import 'package:cosmetix/widgets/why_it_suits_card.dart';

/// Final Beauty Profile: what the questionnaire (and the optional photo)
/// found. It is already saved and now drives the recommendations.
class ColorResultScreen extends StatelessWidget {
  const ColorResultScreen({super.key, required this.result});

  final BeautyResultArgs result;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final p = result.profile;
    final colorType = p.colorType?.label ?? '';
    final palette = ColorPalettes.seasons[p.colorType ?? ColorType.spring]!;
    final description = ColorTestResult(
      colorType: colorType,
      undertone: p.undertone?.label ?? '',
      skinTone: p.skinTone?.label ?? '',
    ).description;
    final concerns = p.concerns.isEmpty
        ? '—'
        : p.concerns.map((c) => tr(c.label)).join(' / ');
    final photoLine = result.photoUsed
        ? tr('Опросник + анализ фото')
        : tr('Опросник');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _done(context);
      },
      child: PageScaffold(
        title: tr('Бьюти-профиль'),
        onBack: () => _done(context),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: context.pal.pinkSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.local_florist,
                  size: 48,
                  color: context.pal.accent,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                trf('Ваш цветотип: {v0}', {'v0': tr(colorType)}),
                style: AppTextStyles.h2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tr(description),
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(color: pal.subtext),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _Info(
                    label: tr('ТИП КОЖИ'),
                    value: p.skinType?.label ?? '—',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Info(
                    label: tr('ТОН КОЖИ'),
                    value: p.skinTone?.label ?? '—',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _Info(
                    label: tr('ПОДТОН'),
                    value: p.undertone?.label ?? '—',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Info(label: tr('ЦВЕТОТИП'), value: colorType),
                ),
              ],
            ),
            const SizedBox(height: 10),
            AppCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('ПРОБЛЕМЫ КОЖИ'),
                    style: AppTextStyles.label.copyWith(color: pal.subtext),
                  ),
                  const SizedBox(height: 4),
                  Text(concerns, style: AppTextStyles.subtitle),
                  const SizedBox(height: 10),
                  Text(
                    tr('ОПРЕДЕЛЕНО ПО'),
                    style: AppTextStyles.label.copyWith(color: pal.subtext),
                  ),
                  const SizedBox(height: 4),
                  Text(photoLine, style: AppTextStyles.subtitle),
                  for (final o in result.observations)
                    Text(
                      '• $o',
                      style: AppTextStyles.caption.copyWith(color: pal.subtext),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(tr('Ваши оттенки'), style: AppTextStyles.subtitle),
            PaletteBlocks(palette: palette),
            const SizedBox(height: 10),
            CustomButton(
              label: tr('Палитры всех цветотипов'),
              outlined: true,
              onPressed: () => Navigator.pushNamed(
                context,
                AppRoutes.palettes,
                arguments: p.colorType,
              ),
            ),
            const _ShadePicks(),
            const SizedBox(height: 14),
            Text(
              tr('Результат сохранён в вашем бьюти-профиле.'),
              textAlign: TextAlign.center,
              style: AppTextStyles.small.copyWith(color: pal.subtext),
            ),
            const SizedBox(height: 20),
            CustomButton(
              label: tr('Подобрать косметику для меня'),
              onPressed: () => Navigator.pushNamed(
                context,
                AppRoutes.catalog,
                arguments: const CatalogArgs(),
              ),
            ),
            const SizedBox(height: 10),
            CustomButton(
              label: tr('Пройти тест заново'),
              outlined: true,
              onPressed: () {
                _done(context);
                Navigator.pushNamed(context, AppRoutes.colorTest);
              },
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => _done(context),
              child: Text(tr('Готово')),
            ),
          ],
        ),
      ),
    );
  }

  /// Back to the Beauty Profile when it is open under this screen, otherwise to
  /// the first screen. A plain `ModalRoute.withName` would pop EVERY route when
  /// the test was started from the cabinet or the home screen (the profile is
  /// not in the stack then) and leave a black page.
  void _done(BuildContext context) => Navigator.of(
    context,
  ).popUntil((r) => r.isFirst || r.settings.name == AppRoutes.beautyProfile);
}

class _Info extends StatelessWidget {
  const _Info({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.label.copyWith(color: context.pal.subtext),
        ),
        const SizedBox(height: 4),
        Text(tr(value), style: AppTextStyles.subtitle),
      ],
    ),
  );
}

/// Named colour dots (a palette group).
class Swatches extends StatelessWidget {
  const Swatches({super.key, required this.colors, this.muted = false});

  final List<PaletteColor> colors;
  final bool muted;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 10,
    children: [
      for (final c in colors)
        SizedBox(
          width: 70,
          child: Column(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  CircleAvatar(radius: 24, backgroundColor: Color(c.argb)),
                  if (muted)
                    const Icon(Icons.close, color: Colors.white, size: 22),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                tr(c.name),
                textAlign: TextAlign.center,
                maxLines: 2,
                style: AppTextStyles.caption.copyWith(
                  color: context.pal.subtext,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

/// Makeup from the catalog whose real shade is closest to the person's
/// palette (or skin tone for a base), with the reason.
class _ShadePicks extends StatelessWidget {
  const _ShadePicks();

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    if (!catalog.hasProfile) return const SizedBox.shrink();
    final ranked = catalog
        .recommend([
          for (final p in catalog.products)
            if (p.category == 'Макияж' && p.shade != null) p,
        ])
        .take(3)
        .toList();
    if (ranked.isEmpty) return const SizedBox.shrink();
    const shadeTypes = {
      MatchReasonType.shadeFit,
      MatchReasonType.shadeOff,
      MatchReasonType.skinShade,
      MatchReasonType.skinShadeOff,
    };
    String note(Recommendation r) {
      final why = r.reasons.where((x) => shadeTypes.contains(x.type));
      final text = why.isEmpty
          ? ''
          : ' · ${WhyItSuitsCard.reasonText(why.first)}';
      return '${r.matchPercent}%$text';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        Text(tr('Из каталога вам идут'), style: AppTextStyles.subtitle),
        for (final r in ranked)
          ProductMiniCard(productId: r.product.id, note: note(r)),
      ],
    );
  }
}

/// All blocks of one palette (lips, blush, eyes, clothes, metals) and the
/// colours to avoid.
class PaletteBlocks extends StatelessWidget {
  const PaletteBlocks({super.key, required this.palette});

  final SeasonPalette palette;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final g in palette.groups) ...[
          const SizedBox(height: 12),
          Text(
            tr(g.title),
            style: AppTextStyles.small.copyWith(
              color: pal.subtext,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Swatches(colors: g.colors),
        ],
        const SizedBox(height: 16),
        Text(tr('Лучше избегать'), style: AppTextStyles.subtitle),
        const SizedBox(height: 10),
        Swatches(colors: palette.avoid, muted: true),
      ],
    );
  }
}
