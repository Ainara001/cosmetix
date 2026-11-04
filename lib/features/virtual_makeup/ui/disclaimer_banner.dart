import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

/// Always on screen: the result is a preview, not a promise.
class DisclaimerBanner extends StatelessWidget {
  const DisclaimerBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Container(
      key: const Key('vm-disclaimer'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: pal.amberSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: pal.text),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr(
                'Виртуальная примерка: приблизительный результат, а не гарантия реального макияжа. Кожа не ретушируется: поры, прыщи, рубцы и покраснения остаются.',
              ),
              style: AppTextStyles.small.copyWith(color: pal.text),
            ),
          ),
        ],
      ),
    );
  }
}
