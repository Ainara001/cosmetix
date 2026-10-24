import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/formatters.dart';
import 'package:cosmetix/models/care_models.dart';
import 'package:cosmetix/providers/care_provider.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/common_widgets.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';

/// What the user marked as used during the last 30 days, day by day.
class CareHistoryScreen extends StatelessWidget {
  const CareHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final care = context.watch<CareProvider>();
    final pal = context.pal;
    final days = care.historyByDay;

    List<Widget> section(String title, List<CareLogEntry> items) => [
      if (items.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(title, style: AppTextStyles.label.copyWith(color: pal.subtext)),
        for (final e in items)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('• ${e.productName}', style: AppTextStyles.small),
          ),
      ],
    ];

    return PageScaffold(
      title: tr('История ухода'),
      bigTitle: true,
      showNav: false,
      child: days.isEmpty
          ? EmptyState(
              icon: Icons.history,
              title: tr('История пока пуста'),
              subtitle: tr(
                'Отмечайте использованные средства в плане ухода, и они появятся здесь.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                for (final entry in days.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            Formatters.date(entry.key),
                            style: AppTextStyles.bodyBold,
                          ),
                          ...section(tr('УТРО'), [
                            for (final e in entry.value)
                              if (e.period == CarePeriod.morning) e,
                          ]),
                          ...section(tr('ВЕЧЕР'), [
                            for (final e in entry.value)
                              if (e.period == CarePeriod.evening) e,
                          ]),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
