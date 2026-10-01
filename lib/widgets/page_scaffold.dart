import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/material.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'app_bottom_nav.dart';

/// Screen frame: back arrow + title (Figma style) and optional bottom nav.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.showNav = true,
    this.onBack,
    this.centerTitle = false,
    this.bigTitle = false,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final bool showNav;
  final VoidCallback? onBack;
  final bool centerTitle;
  final bool bigTitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: !showNav,
        child: Column(
          children: [
            BackTitleBar(
              title: title,
              trailing: trailing,
              onBack: onBack,
              centerTitle: centerTitle,
              bigTitle: bigTitle,
            ),
            Expanded(child: child),
          ],
        ),
      ),
      bottomNavigationBar: showNav ? const AppBottomNav() : null,
    );
  }
}

class BackTitleBar extends StatelessWidget {
  const BackTitleBar({
    super.key,
    required this.title,
    this.trailing,
    this.onBack,
    this.centerTitle = false,
    this.bigTitle = false,
  });

  final String title;
  final Widget? trailing;
  final VoidCallback? onBack;
  final bool centerTitle;
  final bool bigTitle;

  @override
  Widget build(BuildContext context) {
    final titleWidget = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: (bigTitle ? AppTextStyles.h2 : AppTextStyles.title),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: tr('Назад'),
            onPressed: onBack ?? () => Navigator.of(context).maybePop(),
            icon: const Icon(
              Icons.chevron_left,
              color: AppColors.primaryDark,
              size: 30,
            ),
          ),
          Expanded(
            child: centerTitle ? Center(child: titleWidget) : titleWidget,
          ),
          trailing ?? SizedBox(width: centerTitle ? 48 : 0),
        ],
      ),
    );
  }
}
