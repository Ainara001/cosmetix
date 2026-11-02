import 'package:flutter/material.dart';

import 'package:cosmetix/core/beauty/beauty_codes.dart';
import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/routes/route_args.dart';
import 'package:cosmetix/services/beauty_test_flow.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/custom_button.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';

/// Beauty Test, skin questions: skin type and skin concerns. The result
/// (together with the colour test) drives the personal recommendations.
class SkinTestScreen extends StatefulWidget {
  const SkinTestScreen({super.key, required this.args});

  final SkinTestArgs args;

  @override
  State<SkinTestScreen> createState() => _SkinTestScreenState();
}

class _SkinTestScreenState extends State<SkinTestScreen> {
  SkinType? _skinType;
  final Set<SkinConcern> _concerns = {};

  void _next() {
    if (_skinType == null) {
      showMessage(
        context,
        tr('Выберите, как ведёт себя ваша кожа'),
        type: MessageType.warning,
      );
      return;
    }
    Navigator.pushNamed(
      context,
      AppRoutes.beautyPhoto,
      arguments: BeautyPhotoArgs(
        color: widget.args.color,
        skinType: _skinType!,
        concerns: {..._concerns},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return PageScaffold(
      title: tr('Тест: ваша кожа'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(
            tr('Как кожа ведёт себя через пару часов после умывания?'),
            style: AppTextStyles.title,
          ),
          const SizedBox(height: 4),
          Text(
            tr(
              'Тип кожи определяется по вашим ответам — по фото его не угадать.',
            ),
            style: AppTextStyles.small.copyWith(color: pal.subtext),
          ),
          const SizedBox(height: 12),
          for (final o in SkinTestQuestions.skinTypeOptions)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                onTap: () => setState(() => _skinType = o.$1),
                borderColor: _skinType == o.$1 ? AppColors.primaryDark : null,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr(o.$3), style: AppTextStyles.bodyBold),
                          Text(
                            tr(o.$2),
                            style: AppTextStyles.small.copyWith(
                              color: pal.subtext,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      _skinType == o.$1
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: _skinType == o.$1
                          ? context.pal.accent
                          : pal.subtext,
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            tr('Что вас беспокоит? (можно выбрать несколько)'),
            style: AppTextStyles.title,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in SkinConcern.values)
                FilterChip(
                  label: Text(tr(c.label)),
                  selected: _concerns.contains(c),
                  selectedColor: AppColors.primarySoft,
                  checkmarkColor: AppColors.primaryDark,
                  onSelected: (v) => setState(() {
                    v ? _concerns.add(c) : _concerns.remove(c);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 24),
          CustomButton(label: tr('Далее'), onPressed: _next),
        ],
      ),
    );
  }
}
