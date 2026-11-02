import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/material.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/routes/route_args.dart';
import 'package:cosmetix/services/color_test_service.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/custom_button.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';

/// Colour-type questionnaire (eyes, hair, skin, sun, blush, jewellery,
/// contrast, white vs cream).
class ColorTestScreen extends StatefulWidget {
  const ColorTestScreen({super.key});

  @override
  State<ColorTestScreen> createState() => _ColorTestScreenState();
}

class _ColorTestScreenState extends State<ColorTestScreen> {
  static final _steps = ColorTestService.questions;

  int _step = 0;

  /// null = not answered yet, -1 = "I don't know" (skipped), else the option.
  final List<int?> _answers = List.filled(_steps.length, null);

  static const _skipped = -1;

  int get _answeredCount => _answers.where((a) => a != null && a >= 0).length;

  void _back() {
    if (_step == 0) {
      Navigator.of(context).maybePop();
    } else {
      setState(() => _step--);
    }
  }

  /// "I don't know": the question is skipped and the AI / other answers decide.
  void _skip() {
    setState(() => _answers[_step] = _skipped);
    _next();
  }

  /// No answers at all: the colour type is determined from a photo by the AI.
  void _byPhoto() => Navigator.pushNamed(
    context,
    AppRoutes.skinTest,
    arguments: const SkinTestArgs(color: ColorTestResult.unknown()),
  );

  void _next() {
    if (_answers[_step] == null) {
      showMessage(
        context,
        tr('Выберите вариант или нажмите «Не знаю»'),
        type: MessageType.warning,
      );
      return;
    }
    if (_step < _steps.length - 1) {
      setState(() => _step++);
      return;
    }
    var warm = 0, depth = 0, contrast = 0;
    for (var i = 0; i < _steps.length; i++) {
      if (_answers[i]! < 0) continue; // skipped: adds nothing
      final o = _steps[i].options[_answers[i]!];
      warm += o.warm;
      depth += o.depth;
      contrast += o.contrast;
    }
    Navigator.pushNamed(
      context,
      AppRoutes.undertoneTest,
      arguments: UndertoneArgs(
        warm: warm,
        depth: depth,
        contrast: contrast,
        answered: _answeredCount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final q = _steps[_step];

    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _step--);
      },
      child: PageScaffold(
        title: tr('Тест цветотипа'),
        onBack: _back,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ListView(
                  children: [
                    Row(
                      children: [
                        Text(
                          trf('Шаг {v0} из {v1}', {
                            'v0': _step + 1,
                            'v1': _steps.length,
                          }),
                          style: AppTextStyles.small.copyWith(
                            color: pal.subtext,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          tr(q.section),
                          style: AppTextStyles.small.copyWith(
                            color: context.pal.accent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (_step + 1) / _steps.length,
                        minHeight: 6,
                        color: AppColors.primary,
                        backgroundColor: AppColors.primarySoft,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_step == 0)
                      AppCard(
                        color: AppColors.primarySoft,
                        borderColor: Colors.transparent,
                        onTap: _byPhoto,
                        child: Row(
                          children: [
                            Icon(Icons.auto_awesome, color: context.pal.accent),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                tr(
                                  'Не знаете ответов? ИИ определит цветотип по фото за вас',
                                ),
                                style: AppTextStyles.small,
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text(tr(q.question), style: AppTextStyles.title),
                    const SizedBox(height: 14),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.95,
                      children: [
                        for (var i = 0; i < q.options.length; i++)
                          _OptionCard(
                            option: q.options[i],
                            selected: _answers[_step] == i,
                            onTap: () => setState(() => _answers[_step] = i),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _skip,
                child: Text(tr('Не знаю — пропустить')),
              ),
              CustomButton(
                label: _step == _steps.length - 1
                    ? tr('К тесту на подтон')
                    : tr('Далее'),
                onPressed: _next,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final ColorOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(8),
      borderColor: selected ? AppColors.primaryDark : null,
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: option.color.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: CircleAvatar(
                  radius: 28,
                  backgroundColor: option.color,
                  child: selected
                      ? const Icon(Icons.check, color: Colors.white, size: 28)
                      : const Icon(
                          Icons.person_outline,
                          color: Colors.white,
                          size: 28,
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            tr(option.title),
            textAlign: TextAlign.center,
            maxLines: 2,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
