import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/constants/app_constants.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/providers/auth_provider.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/common_widgets.dart';
import 'package:cosmetix/widgets/custom_button.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';

class BeautyProfileScreen extends StatelessWidget {
  const BeautyProfileScreen({super.key});

  Future<void> _pick(
    BuildContext context, {
    required String title,
    required List<String> options,
    required String current,
    required Future<void> Function(String) onSave,
  }) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: AppTextStyles.title),
            const SizedBox(height: 8),
            for (final o in options)
              ListTile(
                title: Text(o),
                trailing: o == current
                    ? const Icon(Icons.check, color: AppColors.primaryDark)
                    : null,
                onTap: () => Navigator.pop(ctx, o),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || picked == current) return;
    await onSave(picked);
    if (context.mounted) {
      showMessage(context, 'Сохранено: $picked', type: MessageType.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    if (user == null) {
      return const PageScaffold(title: 'Бьюти-профиль', child: SizedBox());
    }
    final pal = context.pal;

    Widget tile(
      String label,
      String value,
      VoidCallback onTap, {
      bool accent = false,
      String? trailing,
    }) {
      return AppCard(
        onTap: onTap,
        color: accent ? AppColors.primarySoft : null,
        borderColor: accent ? Colors.transparent : null,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: AppTextStyles.label.copyWith(
                color: accent ? AppColors.primaryDark : pal.subtext,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value.isEmpty ? '—' : value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: accent ? AppColors.primaryDark : pal.text,
              ),
            ),
          ],
        ),
      );
    }

    return PageScaffold(
      title: 'Бьюти-профиль',
      bigTitle: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(
            'Ваши индивидуальные особенности кожи и цветотипа для более '
            'точного подбора косметики.',
            style: AppTextStyles.small.copyWith(color: pal.subtext),
          ),
          const SizedBox(height: 14),
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              // grows with the system font size, so the tile never overflows
              mainAxisExtent: MediaQuery.textScalerOf(context).scale(76),
            ),
            children: [
              tile(
                'Тип кожи',
                user.skinType,
                () => _pick(
                  context,
                  title: 'Тип кожи',
                  options: AppConstants.skinTypes,
                  current: user.skinType,
                  onSave: (v) => auth.updateBeauty(skinType: v),
                ),
              ),
              tile(
                'Тон кожи',
                user.skinTone,
                () => _pick(
                  context,
                  title: 'Тон кожи',
                  options: AppConstants.skinTones,
                  current: user.skinTone,
                  onSave: (v) => auth.updateBeauty(skinTone: v),
                ),
              ),
              tile(
                'Подтон',
                user.undertone,
                () => _pick(
                  context,
                  title: 'Подтон',
                  options: AppConstants.undertones,
                  current: user.undertone,
                  onSave: (v) => auth.updateBeauty(undertone: v),
                ),
              ),
              tile(
                'Цветотип',
                user.colorType,
                () => _pick(
                  context,
                  title: 'Цветотип',
                  options: AppConstants.colorTypes,
                  current: user.colorType,
                  onSave: (v) => auth.updateBeauty(colorType: v),
                ),
                accent: true,
              ),
            ],
          ),
          const SectionTitle('Проблемы кожи (фокус ухода)'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final c in AppConstants.skinConcerns)
                  CheckboxListTile(
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(c, style: const TextStyle(fontSize: 14)),
                    value: user.skinConcerns.contains(c),
                    onChanged: (v) {
                      final list = [...user.skinConcerns];
                      v == true ? list.add(c) : list.remove(c);
                      auth.updateBeauty(skinConcerns: list);
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          CustomButton(
            label: 'Пройти бьюти-тест заново',
            outlined: true,
            onPressed: () => Navigator.pushNamed(context, AppRoutes.colorTest),
          ),
        ],
      ),
    );
  }
}
