import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/providers/auth_provider.dart';
import 'package:cosmetix/services/avatar_service.dart';

/// Tap on the avatar: take a photo, choose from the gallery, remove it, or
/// (optionally) pick a color for the placeholder.
Future<void> showAvatarSheet(
  BuildContext context, {
  VoidCallback? onPickColor,
}) async {
  final auth = context.read<AuthProvider>();
  final service = context.read<AvatarService>();
  final hasPhoto = auth.user?.avatarPath != null;
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(tr('Сделать фото')),
            onTap: () => Navigator.pop(ctx, 'camera'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(tr('Выбрать из галереи')),
            onTap: () => Navigator.pop(ctx, 'gallery'),
          ),
          if (hasPhoto)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(tr('Удалить фото')),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
          if (onPickColor != null)
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: Text(tr('Цвет аватара')),
              onTap: () => Navigator.pop(ctx, 'color'),
            ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  final old = auth.user?.avatarPath;
  try {
    switch (action) {
      case 'color':
        onPickColor?.call();
      case 'remove':
        await auth.setAvatarPath(null);
        await service.delete(old);
        if (context.mounted) {
          showMessage(context, tr('Фото удалено'), type: MessageType.info);
        }
      default:
        final path = await service.pickAndStore(
          action == 'camera' ? ImageSource.camera : ImageSource.gallery,
          auth.userId,
        );
        if (path == null) return; // cancelled
        await auth.setAvatarPath(path);
        await service.delete(old);
        if (context.mounted) {
          showMessage(
            context,
            tr('Фото профиля обновлено'),
            type: MessageType.success,
          );
        }
    }
  } catch (_) {
    if (context.mounted) {
      showMessage(
        context,
        tr('Не удалось получить фото. Проверьте доступ к камере/галерее.'),
        type: MessageType.error,
      );
    }
  }
}
