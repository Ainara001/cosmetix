import 'package:flutter/material.dart';

import 'package:cosmetix/core/theme/app_colors.dart';

enum MessageType { success, error, warning, info }

/// Floating SnackBar with an icon and a color for the message type.
void showMessage(
  BuildContext context,
  String text, {
  MessageType type = MessageType.info,
}) {
  final (color, icon) = switch (type) {
    MessageType.success => (AppColors.success, Icons.check_circle_outline),
    MessageType.error => (AppColors.danger, Icons.error_outline),
    MessageType.warning => (AppColors.warning, Icons.warning_amber_rounded),
    MessageType.info => (const Color(0xFF3A3135), Icons.info_outline),
  };
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: color,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 3),
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
}

/// Yes / No dialog. Returns true when the user confirmed.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Да',
  String cancelLabel = 'Отмена',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel, style: TextStyle(color: ctx.pal.subtext)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            confirmLabel,
            style: TextStyle(
              color: destructive ? AppColors.danger : AppColors.primaryDark,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<void> infoDialog(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text(
            'Понятно',
            style: TextStyle(color: AppColors.primaryDark),
          ),
        ),
      ],
    ),
  );
}
