import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Profile avatar photo. Unlike the Beauty Test photo (temporary), this one is
/// kept: it is copied into the application documents directory and its path
/// goes to `users.avatar_path`. The picker's own path is only a cache.
class AvatarService {
  AvatarService({Future<Directory> Function()? documentsDir})
    : _documentsDir = documentsDir ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _documentsDir;

  /// Copies [source] to a permanent place and returns the new path.
  Future<String> store(File source, int userId) async {
    final dir = Directory(p.join((await _documentsDir()).path, 'avatars'));
    await dir.create(recursive: true);
    final dest = p.join(
      dir.path,
      'avatar_${userId}_${DateTime.now().millisecondsSinceEpoch}'
      '${p.extension(source.path).isEmpty ? '.jpg' : p.extension(source.path)}',
    );
    await source.copy(dest);
    return dest;
  }

  /// Picks a photo (camera or gallery); null when the user cancels.
  Future<String?> pickAndStore(ImageSource source, int userId) async {
    final x = await ImagePicker().pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (x == null) return null;
    return store(File(x.path), userId);
  }

  /// Deletes an old avatar file (ignores a missing file).
  Future<void> delete(String? path) async {
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
