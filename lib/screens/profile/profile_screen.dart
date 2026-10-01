import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/providers/auth_provider.dart';
import 'package:cosmetix/providers/nav_provider.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/common_widgets.dart';
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
          BackTitleBar(
            title: 'Профиль',
            centerTitle: true,
            onBack: () => context.read<NavProvider>().setTab(NavProvider.home),
          ),
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
                            UserAvatar(size: 104, color: user.avatarColor),
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
                            const Text(
                              'Редактировать профиль',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.primaryDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.salmon,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _Stat(
                                label: 'БОНУСЫ',
                                value: '${user.bonusPoints}',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _Stat(
                                label: 'ПОСЕЩЕНИЯ',
                                value: '${user.visits}',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      MenuTile(
                        icon: Icons.shopping_cart_outlined,
                        title: 'Покупки',
                        onTap: () =>
                            Navigator.pushNamed(context, AppRoutes.orders),
                      ),
                      MenuTile(
                        icon: Icons.favorite_border,
                        title: 'Избранное',
                        onTap: () =>
                            Navigator.pushNamed(context, AppRoutes.favorites),
                      ),
                      MenuTile(
                        icon: Icons.sentiment_satisfied_alt_outlined,
                        title: 'Цветотип',
                        subtitle: user.colorType.isEmpty
                            ? 'Пройдите тест'
                            : user.colorType,
                        onTap: () => Navigator.pushNamed(
                          context,
                          AppRoutes.beautyProfile,
                        ),
                      ),
                      MenuTile(
                        icon: Icons.settings,
                        title: 'Настройки',
                        onTap: () =>
                            Navigator.pushNamed(context, AppRoutes.settings),
                      ),
                      MenuTile(
                        icon: Icons.healing_outlined,
                        title: 'Дневник Аллергии',
                        onTap: () =>
                            Navigator.pushNamed(context, AppRoutes.reactions),
                      ),
                      MenuTile(
                        icon: Icons.block,
                        title: 'Чёрный список',
                        onTap: () =>
                            Navigator.pushNamed(context, AppRoutes.blacklist),
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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF8E8689),
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
