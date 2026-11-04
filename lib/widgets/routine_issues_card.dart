import 'package:flutter/material.dart';

import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/services/routine_checks.dart';

/// Findings about a set of products: conflicting actives, layering of a
/// foundation, a patch test. Shows nothing when there is nothing to say.
class RoutineIssuesCard extends StatelessWidget {
  const RoutineIssuesCard({
    super.key,
    required this.issues,
    this.title,
    this.padding = const EdgeInsets.only(top: 12),
  });

  final List<RoutineIssue> issues;
  final String? title;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) return const SizedBox.shrink();
    // the same text is shown once; "avoid" first
    final seen = <String>{};
    final list = [
      for (final i in issues)
        if (seen.add(i.text)) i,
    ]..sort((a, b) => a.severity.index.compareTo(b.severity.index));
    final worst = list.first.severity;
    final bg = worst == IssueSeverity.avoid
        ? context.pal.redSoft
        : context.pal.amberSoft;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // readable on the tinted card in both themes
    final cautionFg = dark ? const Color(0xFFF0C46E) : const Color(0xFF8A5A0B);
    final avoidFg = dark ? const Color(0xFFFF8F8F) : AppColors.sale;
    final fg = worst == IssueSeverity.avoid ? avoidFg : cautionFg;
    return Padding(
      padding: padding,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  worst == IssueSeverity.avoid
                      ? Icons.error_outline
                      : Icons.warning_amber_rounded,
                  size: 18,
                  color: fg,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title ?? tr('Совместимость средств'),
                    style: AppTextStyles.subtitle.copyWith(color: fg),
                  ),
                ),
              ],
            ),
            for (final i in list)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Icon(
                        Icons.circle,
                        size: 6,
                        color: i.severity == IssueSeverity.avoid
                            ? avoidFg
                            : cautionFg,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(i.text, style: AppTextStyles.small)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
