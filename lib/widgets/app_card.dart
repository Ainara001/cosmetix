import 'package:flutter/material.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_dimensions.dart';

/// White rounded card with a thin border; tappable when [onTap] is given.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(14),
    this.color,
    this.borderColor,
    this.radius = AppDimensions.radius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final shape = BorderRadius.circular(radius);
    return Material(
      color: color ?? pal.surface,
      shape: RoundedRectangleBorder(
        borderRadius: shape,
        side: BorderSide(color: borderColor ?? pal.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
