import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/constants/app_constants.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/formatters.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/providers/session.dart';
import 'package:cosmetix/providers/settings_provider.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/routes/route_args.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    final ok = await confirmDialog(
      context,
      title: tr('Выйти из аккаунта?'),
      message: tr('Вам нужно будет снова войти, чтобы увидеть свои данные.'),
      confirmLabel: tr('Выйти'),
      destructive: true,
    );
    if (ok && context.mounted) await Session.signOut(context);
  }

  Future<void> _resetDemo(BuildContext context) async {
    final ok = await confirmDialog(
      context,
      title: tr('Сбросить демо-данные?'),
      message: tr(
        'Все ваши данные (аккаунты, заказы, избранное, отзывы) будут удалены, а база вернётся к исходным демо-данным.',
      ),
      confirmLabel: tr('Сбросить'),
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final helper = context.read<DatabaseHelper>();
    final settings = context.read<SettingsProvider>();
    try {
      await helper.resetDemoData();
      await settings.load();
      if (!context.mounted) return;
      await Session.signOut(context);
    } catch (_) {
      if (context.mounted) {
        showMessage(
          context,
          tr('Не удалось сбросить данные'),
          type: MessageType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>();
    final pal = context.pal;

    return PageScaffold(
      title: tr('Настройки'),
      bigTitle: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          _Header(tr('УВЕДОМЛЕНИЯ')),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    tr('Пуш-уведомления о скидках'),
                    style: AppTextStyles.bodyBold,
                  ),
                ),
                Switch(
                  value: s.pushEnabled,
                  onChanged: (v) {
                    s.setPush(v);
                    showMessage(
                      context,
                      v
                          ? tr('Уведомления о скидках включены')
                          : tr('Уведомления выключены'),
                      type: v ? MessageType.success : MessageType.info,
                    );
                  },
                ),
              ],
            ),
          ),
          _Header(tr('ПРЕДПОЧТЕНИЯ')),
          _DropdownRow<AppLang>(
            title: tr('Язык приложения'),
            valueLabel: s.language.label,
            items: AppLang.values,
            labelOf: (l) => l.label,
            onSelected: s.setLanguage,
          ),
          const SizedBox(height: 8),
          _DropdownRow<ThemeMode>(
            title: tr('Тема оформления'),
            valueLabel: s.themeMode == ThemeMode.dark
                ? tr('Тёмная')
                : tr('Светлая'),
            items: const [ThemeMode.light, ThemeMode.dark],
            labelOf: (v) => v == ThemeMode.dark ? tr('Тёмная') : tr('Светлая'),
            onSelected: s.setTheme,
          ),
          const SizedBox(height: 8),
          _DropdownRow<AppCurrency>(
            title: tr('Валюта'),
            valueLabel: tr(s.currency.label),
            items: AppCurrency.values,
            labelOf: (v) => tr(v.label),
            onSelected: s.setCurrency,
          ),
          _Header(tr('ИНФОРМАЦИЯ')),
          _LinkRow(
            title: tr('Политика конфиденциальности'),
            onTap: () => Navigator.pushNamed(
              context,
              AppRoutes.legal,
              arguments: LegalArgs.privacy,
            ),
          ),
          const SizedBox(height: 8),
          _LinkRow(
            title: tr('Условия использования'),
            onTap: () => Navigator.pushNamed(
              context,
              AppRoutes.legal,
              arguments: LegalArgs.terms,
            ),
          ),
          const SizedBox(height: 8),
          _LinkRow(
            title: tr('Чёрный список'),
            onTap: () => Navigator.pushNamed(context, AppRoutes.blacklist),
          ),
          const SizedBox(height: 8),
          _LinkRow(
            title: tr('Сбросить демо-данные'),
            onTap: () => _resetDemo(context),
          ),
          const SizedBox(height: 18),
          OutlinedButton(
            onPressed: () => _logout(context),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              foregroundColor: AppColors.sale,
              side: const BorderSide(color: AppColors.sale),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              tr('Выйти из аккаунта'),
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              trf('Версия приложения {v0}', {'v0': AppConstants.version}),
              style: AppTextStyles.caption.copyWith(color: pal.subtext),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text(
      text,
      style: AppTextStyles.label.copyWith(color: context.pal.subtext),
    ),
  );
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppCard(
    onTap: onTap,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    child: Row(
      children: [
        Expanded(child: Text(title, style: AppTextStyles.bodyBold)),
        Icon(Icons.chevron_right, color: context.pal.subtext),
      ],
    ),
  );
}

class _DropdownRow<T> extends StatelessWidget {
  const _DropdownRow({
    required this.title,
    required this.valueLabel,
    required this.items,
    required this.labelOf,
    required this.onSelected,
  });

  final String title;
  final String valueLabel;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return PopupMenuButton<T>(
      tooltip: title,
      onSelected: onSelected,
      position: PopupMenuPosition.under,
      itemBuilder: (_) => [
        for (final i in items) PopupMenuItem(value: i, child: Text(labelOf(i))),
      ],
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Expanded(child: Text(title, style: AppTextStyles.bodyBold)),
            Text(
              valueLabel,
              style: TextStyle(color: pal.subtext, fontSize: 13),
            ),
            Icon(Icons.arrow_drop_down, color: pal.subtext),
          ],
        ),
      ),
    );
  }
}
