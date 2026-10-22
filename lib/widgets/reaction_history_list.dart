import 'package:flutter/material.dart';

import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/formatters.dart';
import 'package:cosmetix/models/safety_models.dart';
import 'package:cosmetix/widgets/app_card.dart';

/// Readable lines for one history entry ("Тяжесть: 2 → 4", "Фото добавлено").
List<String> describeReactionChange(ReactionChange c) {
  if (c.created) return [tr('Запись создана')];
  String day(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? iso : Formatters.date(d);
  }

  String shown(String v) => v.isEmpty ? '—' : v;
  final out = <String>[];
  c.fields.forEach((field, v) {
    final (from, to) = v;
    switch (field) {
      case 'product':
        out.add(trf('Продукт: {a} → {b}', {'a': shown(from), 'b': shown(to)}));
      case 'title':
        out.add(trf('Реакция: {a} → {b}', {'a': tr(from), 'b': tr(to)}));
      case 'severity':
        out.add(trf('Тяжесть: {a} → {b}', {'a': from, 'b': to}));
      case 'date':
        out.add(trf('Дата: {a} → {b}', {'a': day(from), 'b': day(to)}));
      case 'notes':
        out.add(tr('Заметка изменена'));
      case 'photo':
        out.add(
          from == 'none'
              ? tr('Фото добавлено')
              : to == 'none'
              ? tr('Фото удалено')
              : tr('Фото заменено'),
        );
    }
  });
  return out;
}

/// The change history of one diary record (newest first).
class ReactionHistoryList extends StatelessWidget {
  const ReactionHistoryList({super.key, required this.changes});

  final List<ReactionChange> changes;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    if (changes.isEmpty) {
      return Text(
        tr('Изменений пока нет.'),
        style: AppTextStyles.small.copyWith(color: pal.subtext),
      );
    }
    return Column(
      children: [
        for (final c in changes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Formatters.ago(c.changedAt),
                    style: AppTextStyles.caption.copyWith(color: pal.subtext),
                  ),
                  const SizedBox(height: 4),
                  for (final line in describeReactionChange(c))
                    Text(line, style: AppTextStyles.small),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
