import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/constants/app_constants.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/models/beauty_profile.dart';
import 'package:cosmetix/providers/auth_provider.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/routes/route_args.dart';
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
                title: Text(tr(o)),
                trailing: o == current
                    ? Icon(Icons.check, color: context.pal.accent)
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
      showMessage(
        context,
        trf('Сохранено: {picked}', {'picked': picked}),
        type: MessageType.success,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    if (user == null) {
      return PageScaffold(title: tr('Бьюти-профиль'), child: SizedBox());
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
                color: accent ? context.pal.accent : pal.subtext,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value.isEmpty ? '—' : tr(value),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: accent ? context.pal.accent : pal.text,
              ),
            ),
          ],
        ),
      );
    }

    return PageScaffold(
      title: tr('Бьюти-профиль'),
      bigTitle: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(
            tr(
              'Ваши индивидуальные особенности кожи и цветотипа для более точного подбора косметики.',
            ),
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
              mainAxisExtent: MediaQuery.textScalerOf(context).scale(100),
            ),
            children: [
              tile(
                tr('Тип кожи'),
                user.skinType,
                () => _pick(
                  context,
                  title: tr('Тип кожи'),
                  options: AppConstants.skinTypes,
                  current: user.skinType,
                  onSave: (v) => auth.updateBeauty(skinType: v),
                ),
              ),
              tile(
                tr('Тон кожи'),
                user.skinTone,
                () => _pick(
                  context,
                  title: tr('Тон кожи'),
                  options: AppConstants.skinTones,
                  current: user.skinTone,
                  onSave: (v) => auth.updateBeauty(skinTone: v),
                ),
              ),
              tile(
                tr('Подтон'),
                user.undertone,
                () => _pick(
                  context,
                  title: tr('Подтон'),
                  options: AppConstants.undertones,
                  current: user.undertone,
                  onSave: (v) => auth.updateBeauty(undertone: v),
                ),
              ),
              tile(
                tr('Цветотип'),
                user.colorType,
                () => _pick(
                  context,
                  title: tr('Цветотип'),
                  options: AppConstants.colorTypes,
                  current: user.colorType,
                  onSave: (v) => auth.updateBeauty(colorType: v),
                ),
                accent: true,
              ),
            ],
          ),
          SectionTitle(tr('Проблемы кожи (фокус ухода)')),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final c in AppConstants.skinConcerns)
                  CheckboxListTile(
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(tr(c), style: const TextStyle(fontSize: 14)),
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
          SectionTitle(tr('Личные предпочтения')),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final code in Preferences.all)
                      AppChip(
                        label: tr(Preferences.label(code)),
                        selected: user.preferences.contains(code),
                        onTap: () {
                          final next = {...user.preferences};
                          next.contains(code)
                              ? next.remove(code)
                              : next.add(code);
                          auth.updatePreferences(preferences: next);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  tr(
                    'Предпочтения слегка меняют порядок рекомендаций, но не скрывают товары.',
                  ),
                  style: AppTextStyles.caption.copyWith(color: pal.subtext),
                ),
                const Divider(height: 22),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  activeThumbColor: AppColors.primaryDark,
                  title: Text(
                    tr('Учитывать мои реакции и косметичку'),
                    style: AppTextStyles.small,
                  ),
                  subtitle: Text(
                    tr(
                      'Средства, на которые вы отмечали реакцию, будут ниже в рекомендациях. Данные остаются на телефоне.',
                    ),
                    style: AppTextStyles.caption.copyWith(color: pal.subtext),
                  ),
                  value: user.recoUseHistory,
                  onChanged: (v) => auth.updatePreferences(useHistory: v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            user.beautySource == 'questionnaire_photo'
                ? tr('Определено по: опросник + анализ фото')
                : tr('Определено по: опросник'),
            style: AppTextStyles.caption.copyWith(color: pal.subtext),
          ),
          const SizedBox(height: 14),
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
            label: tr('Палитры цветотипов'),
            outlined: true,
            onPressed: () => Navigator.pushNamed(
              context,
              AppRoutes.palettes,
              arguments: user.beautyProfile.colorType,
            ),
          ),
          const SizedBox(height: 10),
          CustomButton(
            label: tr('Пройти бьюти-тест заново'),
            outlined: true,
            onPressed: () => Navigator.pushNamed(context, AppRoutes.colorTest),
          ),
        ],
      ),
    );
  }
}
