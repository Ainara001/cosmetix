import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/material.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/routes/route_args.dart';
import 'package:cosmetix/services/color_test_service.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/custom_button.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';

/// Final Beauty Profile: what the questionnaire (and the optional photo)
/// found. It is already saved and now drives the recommendations.
class ColorResultScreen extends StatelessWidget {
  const ColorResultScreen({super.key, required this.result});

  final BeautyResultArgs result;

  static const _palettes = {
    'Весна': [0xFFF6B8A0, 0xFFF3C969, 0xFFE9967A, 0xFFB5D99C, 0xFFFFD9B3],
    'Лето': [0xFFE5A1B5, 0xFFB9A3D6, 0xFF9FB8D6, 0xFFD7B5C8, 0xFFC9D6EA],
    'Осень': [0xFFB5532F, 0xFFC98B2F, 0xFF7A8450, 0xFF8A5A3C, 0xFFD9A066],
    'Зима': [0xFF8E1E4A, 0xFF1F3C88, 0xFF5B2A86, 0xFFD6336C, 0xFF222222],
  };

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final p = result.profile;
    final colorType = p.colorType?.label ?? '';
    final colors = _palettes[colorType] ?? _palettes['Весна']!;
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
                decoration: const BoxDecoration(
                  color: AppColors.primarySoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.local_florist,
                  size: 48,
                  color: AppColors.primaryDark,
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
                  if (result.photoUsed && p.confidence != null)
                    Text(
                      trf('Уверенность анализа фото: {n}%', {
                        'n': (p.confidence! * 100).round(),
                      }),
                      style: AppTextStyles.caption.copyWith(color: pal.subtext),
                    ),
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
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final c in colors)
                  CircleAvatar(radius: 24, backgroundColor: Color(c)),
              ],
            ),
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

  void _done(BuildContext context) => Navigator.of(
    context,
  ).popUntil(ModalRoute.withName(AppRoutes.beautyProfile));
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
