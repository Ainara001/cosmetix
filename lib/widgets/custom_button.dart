import 'package:flutter/material.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_dimensions.dart';

/// Pill button from the Figma design: filled (default) or outlined.
class CustomButton extends StatelessWidget {
  const CustomButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.outlined = false,
    this.loading = false,
    this.icon,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool outlined;
  final bool loading;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final main = color ?? AppColors.primary;
    final child = loading
        ? SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: outlined ? main : Colors.white,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppDimensions.radiusPill),
    );
    final size = const Size.fromHeight(AppDimensions.buttonHeight);
    final action = loading ? null : onPressed;

    if (outlined) {
      return OutlinedButton(
        onPressed: action,
        style: OutlinedButton.styleFrom(
          minimumSize: size,
          shape: shape,
          foregroundColor: color ?? AppColors.primaryDark,
          side: BorderSide(color: main, width: 1.2),
          backgroundColor: Colors.transparent,
        ),
        child: child,
      );
    }
    return ElevatedButton(
      onPressed: action,
      style: ElevatedButton.styleFrom(
        minimumSize: size,
        shape: shape,
        elevation: 0,
        backgroundColor: main,
        foregroundColor: Colors.white,
        disabledBackgroundColor: main.withValues(alpha: 0.5),
        disabledForegroundColor: Colors.white,
      ),
      child: child,
    );
  }
}
