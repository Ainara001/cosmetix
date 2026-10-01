import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/providers/auth_provider.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/routes/route_args.dart';
import 'package:cosmetix/services/color_test_service.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/custom_button.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';

class UndertoneTestScreen extends StatefulWidget {
  const UndertoneTestScreen({super.key, required this.args});

  final UndertoneArgs args;

  @override
  State<UndertoneTestScreen> createState() => _UndertoneTestScreenState();
}

class _UndertoneTestScreenState extends State<UndertoneTestScreen> {
  int? _selected;
  bool _saving = false;

  Future<void> _finish() async {
    if (_selected == null) {
      showMessage(context, tr('Выберите цвет вен'), type: MessageType.warning);
      return;
    }
    setState(() => _saving = true);
    final result = ColorTestService.compute(
      warm: widget.args.warm,
      depth: widget.args.depth,
      vein: ColorTestService.veinQuestion[_selected!].$4,
    );
    try {
      await context.read<AuthProvider>().updateBeauty(
        colorType: result.colorType,
        undertone: result.undertone,
        skinTone: result.skinTone,
      );
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        AppRoutes.colorResult,
        arguments: result,
      );
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        showMessage(
          context,
          tr('Не удалось сохранить результат'),
          type: MessageType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return PageScaffold(
      title: tr('Тест на подтон кожи'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          AppCard(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                Container(
                  height: 130,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1D7C8),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: CustomPaint(
                    painter: _WristPainter(),
                    size: Size.infinite,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tr(
                    'Посмотрите на вены на вашем запястье при естественном освещении.',
                  ),
                  textAlign: TextAlign.center,
                  style: AppTextStyles.small.copyWith(color: pal.subtext),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            tr('Какого цвета вены на вашем запястье?'),
            style: AppTextStyles.title,
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < ColorTestService.veinQuestion.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                onTap: () => setState(() => _selected = i),
                borderColor: _selected == i ? AppColors.primaryDark : null,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 9,
                      backgroundColor: ColorTestService.veinQuestion[i].$3,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ColorTestService.veinQuestion[i].$1,
                            style: AppTextStyles.bodyBold,
                          ),
                          Text(
                            ColorTestService.veinQuestion[i].$2,
                            style: AppTextStyles.caption.copyWith(
                              color: pal.subtext,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      _selected == i
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: _selected == i
                          ? AppColors.primaryDark
                          : pal.border,
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),
          CustomButton(
            label: tr('Завершить и показать результат'),
            loading: _saving,
            onPressed: _finish,
          ),
        ],
      ),
    );
  }
}

/// A simple drawn wrist with veins (no external image needed).
class _WristPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final skin = Paint()..color = const Color(0xFFE7B99F);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.12,
          size.height * 0.22,
          size.width * 0.76,
          size.height * 0.56,
        ),
        const Radius.circular(40),
      ),
      skin,
    );
    final vein = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF6E7FB2);
    for (var i = 0; i < 3; i++) {
      final y = size.height * (0.38 + i * 0.12);
      final path = Path()
        ..moveTo(size.width * 0.22, y)
        ..quadraticBezierTo(
          size.width * 0.5,
          y - 14 + i * 8,
          size.width * 0.78,
          y + 4,
        );
      canvas.drawPath(path, vein);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
