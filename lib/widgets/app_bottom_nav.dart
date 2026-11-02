import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/providers/cart_provider.dart';
import 'package:cosmetix/providers/nav_provider.dart';

/// Bottom navigation shown on the main tabs and on pushed screens.
/// Tapping a tab selects it and returns to the main shell.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key});

  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, 'Главная'),
    (Icons.shopping_cart_outlined, Icons.shopping_cart, 'Корзина'),
    (
      Icons.sentiment_satisfied_alt_outlined,
      Icons.sentiment_satisfied_alt,
      'ИИ Чат',
    ),
    (Icons.person_outline, Icons.person, 'Кабинет'),
  ];

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final nav = context.watch<NavProvider>();
    final cartCount = context.select<CartProvider, int>((c) => c.count);

    return Container(
      decoration: BoxDecoration(
        color: pal.surface,
        border: Border(top: BorderSide(color: pal.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          // grows with the system font size so the labels never overflow
          height: 62 + (MediaQuery.textScalerOf(context).scale(11) - 11) * 2,
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () {
                      context.read<NavProvider>().setTab(i);
                      Navigator.of(context).popUntil((r) => r.isFirst);
                    },
                    child: _NavItem(
                      icon: nav.tab == i ? _items[i].$2 : _items[i].$1,
                      label: tr(_items[i].$3),
                      active: nav.tab == i,
                      badge: i == NavProvider.cart ? cartCount : 0,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.badge,
  });

  final IconData icon;
  final String label;
  final bool active;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final color = active ? context.pal.accent : context.pal.subtext;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Badge(
          isLabelVisible: badge > 0,
          label: Text('$badge'),
          backgroundColor: AppColors.sale,
          child: Icon(icon, color: color, size: 26),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
