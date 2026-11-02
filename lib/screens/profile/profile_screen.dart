import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/models/app_user.dart';
import 'package:cosmetix/providers/auth_provider.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/avatar_sheet.dart';
import 'package:cosmetix/widgets/common_widgets.dart';
import 'package:cosmetix/widgets/custom_button.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final pal = context.pal;

    return SafeArea(
      child: Column(
        children: [
          BackTitleBar(title: tr('Профиль'), bigTitle: true, showBack: false),
          Expanded(
            child: user == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    children: [
                      AppCard(
                        radius: 20,
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        onTap: () =>
                            Navigator.pushNamed(context, AppRoutes.editProfile),
                        child: Column(
                          children: [
                            GestureDetector(
                              onTap: () => showAvatarSheet(context),
                              child: Stack(
                                children: [
                                  UserAvatar(
                                    size: 104,
                                    color: user.avatarColor,
                                    photoPath: user.avatarPath,
                                  ),
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: pal.surface,
                                          width: 2,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.photo_camera,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              user.fullName.isEmpty
                                  ? user.email
                                  : user.fullName,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFB5788A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              user.email,
                              style: AppTextStyles.small.copyWith(
                                color: pal.subtext,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              tr('Редактировать профиль'),
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.primaryDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _Stat(
                              label: tr('БОНУСЫ'),
                              value: '${user.bonusPoints}',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _Stat(
                              label: tr('ПОСЕЩЕНИЯ'),
                              value: '${user.visits}',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _BeautySummary(user: user),
                      const SizedBox(height: 14),
                      MenuTile(
                        icon: Icons.shopping_cart_outlined,
                        title: tr('Покупки'),
                        onTap: () =>
                            Navigator.pushNamed(context, AppRoutes.orders),
                      ),
                      MenuTile(
                        icon: Icons.map_outlined,
                        title: tr('Магазины на карте'),
                        subtitle: tr('Подружка, Диона и другие рядом с вами'),
                        onTap: () =>
                            Navigator.pushNamed(context, AppRoutes.stores),
                      ),
                      MenuTile(
                        icon: Icons.favorite_border,
                        title: tr('Избранное'),
                        onTap: () =>
                            Navigator.pushNamed(context, AppRoutes.favorites),
                      ),
                      MenuTile(
                        icon: Icons.shopping_bag_outlined,
                        title: tr('Моя косметичка'),
                        onTap: () =>
                            Navigator.pushNamed(context, AppRoutes.bag),
                      ),
                      MenuTile(
                        icon: Icons.wb_twilight_outlined,
                        title: tr('Мой уход'),
                        onTap: () =>
                            Navigator.pushNamed(context, AppRoutes.care),
                      ),
                      MenuTile(
                        icon: Icons.document_scanner_outlined,
                        title: tr('Проверка состава'),
                        onTap: () =>
                            Navigator.pushNamed(context, AppRoutes.scan),
                      ),
                      MenuTile(
                        icon: Icons.healing_outlined,
                        title: tr('Дневник реакций'),
                        onTap: () =>
                            Navigator.pushNamed(context, AppRoutes.reactions),
                      ),
                      MenuTile(
                        icon: Icons.block,
                        title: tr('Чёрный список'),
                        onTap: () =>
                            Navigator.pushNamed(context, AppRoutes.blacklist),
                      ),
                      MenuTile(
                        icon: Icons.settings,
                        title: tr('Настройки'),
                        onTap: () =>
                            Navigator.pushNamed(context, AppRoutes.settings),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: pal.border),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: pal.subtext,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryDark,
            ),
          ),
        ],
      ),
    );
  }
}

/// Beauty Profile on the profile screen: color type, skin type, undertone and
/// the two actions (edit profile / retake the Beauty Test).
class _BeautySummary extends StatelessWidget {
  const _BeautySummary({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final done = user.hasBeautyProfile;
    Widget cell(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.label.copyWith(color: pal.subtext)),
          const SizedBox(height: 2),
          // one line, scaled down: a long word is never cut in the middle
          FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(
              value.isEmpty ? '—' : tr(value),
              style: AppTextStyles.bodyBold,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
    return AppCard(
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Бьюти-профиль'), style: AppTextStyles.subtitle),
          const SizedBox(height: 10),
          if (done)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                cell(tr('ЦВЕТОТИП'), user.colorType),
                cell(tr('ТИП КОЖИ'), user.skinType),
                cell(tr('ПОДТОН'), user.undertone),
              ],
            )
          else
            Text(
              tr(
                'Пройдите бьюти-тест, чтобы получать персональные рекомендации.',
              ),
              style: AppTextStyles.small.copyWith(color: pal.subtext),
            ),
          const SizedBox(height: 12),
          // editing the profile is the card at the top: one full-width button
          // here, so the label is never cut off
          CustomButton(
            label: done ? tr('Пройти тест заново') : tr('Пройти тест'),
            outlined: done,
            onPressed: () => Navigator.pushNamed(context, AppRoutes.colorTest),
          ),
        ],
      ),
    );
  }
}
