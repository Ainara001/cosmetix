import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:flutter/material.dart';

import 'virtual_makeup_controller.dart';

/// Tools for the protection mask: brush, eraser, size, undo, and the hint.
/// A share of the photo as text: "0.0" only when nothing is protected.
String _percent(double share) {
  final p = share * 100;
  if (p <= 0) return '0.0';
  return p < 0.1 ? '<0.1' : p.toStringAsFixed(1);
}

class MaskEditorPanel extends StatelessWidget {
  const MaskEditorPanel({
    super.key,
    required this.controller,
    required this.erase,
    required this.brushRadius,
    required this.onErase,
    required this.onBrushRadius,
  });

  final VirtualMakeupController controller;
  final bool erase;
  final double brushRadius;
  final ValueChanged<bool> onErase;
  final ValueChanged<double> onBrushRadius;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final c = controller;
    final m = c.protection;
    final s = c.suggestion;
    return AppCard(
      key: const Key('vm-mask-panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(
              'Закрасьте участки, которые должны остаться как на фото: прыщи, рубцы, покраснения, родинки. Здесь макияж не применяется вообще.',
            ),
            style: AppTextStyles.small,
          ),
          const SizedBox(height: 10),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: false,
                icon: const Icon(Icons.brush_outlined),
                label: Text(tr('Кисть')),
              ),
              ButtonSegment(
                value: true,
                icon: const Icon(Icons.cleaning_services_outlined),
                label: Text(tr('Ластик')),
              ),
            ],
            selected: {erase},
            onSelectionChanged: (v) => onErase(v.first),
          ),
          Row(
            children: [
              Text(tr('Размер кисти'), style: AppTextStyles.small),
              Expanded(
                child: Slider(
                  key: const Key('vm-brush-size'),
                  value: brushRadius,
                  min: 0.008,
                  max: 0.06,
                  onChanged: onBrushRadius,
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('vm-undo'),
                onPressed: m != null && m.canUndo ? c.undo : null,
                icon: const Icon(Icons.undo),
                label: Text(tr('Отменить')),
              ),
              OutlinedButton.icon(
                key: const Key('vm-redo'),
                onPressed: m != null && m.canRedo ? c.redo : null,
                icon: const Icon(Icons.redo),
                label: Text(tr('Вернуть')),
              ),
              OutlinedButton.icon(
                key: const Key('vm-clear'),
                onPressed: m != null && !m.isEmpty ? c.clearProtection : null,
                icon: const Icon(Icons.delete_outline),
                label: Text(tr('Очистить')),
              ),
            ],
          ),
          if (m != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                trf('Защищено: {v0}% фото', {'v0': _percent(m.coverage)}),
                style: AppTextStyles.caption.copyWith(color: pal.subtext),
              ),
            ),
          const Divider(height: 24),
          Text(
            tr(
              'Подсказка находит только мелкие красные или тёмные пятна и может ошибаться: проверьте и поправьте вручную.',
            ),
            style: AppTextStyles.small.copyWith(color: pal.subtext),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('vm-suggest'),
            onPressed: c.suggest,
            icon: const Icon(Icons.auto_awesome_outlined),
            label: Text(tr('Подсказать участки')),
          ),
          if (s != null) ...[
            const SizedBox(height: 8),
            if (!s.reliable)
              Text(
                tr(
                  'Слишком много участков выделилось (свет или косметика). Подсказка не показана, отметьте участки вручную.',
                ),
                key: const Key('vm-suggest-unreliable'),
                style: AppTextStyles.small,
              )
            else if (s.regions == 0)
              Text(
                tr(
                  'Мелких пятен не найдено. Это не значит, что их нет: отметьте нужные участки вручную.',
                ),
                key: const Key('vm-suggest-none'),
                style: AppTextStyles.small,
              )
            else ...[
              Text(
                trf('Найдено участков: {v0}. Проверьте их на фото (жёлтые).', {
                  'v0': s.regions,
                }),
                key: const Key('vm-suggest-found'),
                style: AppTextStyles.small,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  FilledButton(
                    key: const Key('vm-suggest-accept'),
                    onPressed: c.acceptSuggestion,
                    child: Text(tr('Защитить')),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    key: const Key('vm-suggest-dismiss'),
                    onPressed: c.dismissSuggestion,
                    child: Text(tr('Отклонить')),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}
