import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Where the app keeps the photos the user chose (avatar, review photos).
///
/// The database stores them as `avatars/<file>` / `review_photos/<file>`
/// instead of absolute paths: on iOS the app folder gets a new absolute path
/// after an update or reinstall, which used to break every saved photo.
/// Absolute paths written by older builds are repaired the same way.
class AppPaths {
  AppPaths._();

  static const avatarsDir = 'avatars';
  static const reviewPhotosDir = 'review_photos';
  static const reactionPhotosDir = 'reaction_photos';

  static const _photoFolders = {avatarsDir, reviewPhotosDir, reactionPhotosDir};

  static String? _documents;
  static String? _databases;

  /// Call once at startup, before the first screen is built.
  static Future<void> init() async {
    _documents = (await getApplicationDocumentsDirectory()).path;
    _databases = await getDatabasesPath();
  }

  @visibleForTesting
  static void setForTest({String? documents, String? databases}) {
    _documents = documents;
    _databases = databases;
  }

  static String? _baseOf(String folder) => switch (folder) {
    avatarsDir => _documents,
    reactionPhotosDir => _documents,
    reviewPhotosDir => _databases,
    _ => null,
  };

  /// Copies [source] into the photo folder [folder] (created on demand) and
  /// returns the new absolute path; store it with [toStored].
  static Future<String> storePhoto(
    File source,
    String folder, {
    String prefix = 'photo',
  }) async {
    final base = _baseOf(folder);
    if (base == null) {
      throw StateError('AppPaths is not initialized');
    }
    final dir = Directory(p.join(base, folder));
    await dir.create(recursive: true);
    final ext = p.extension(source.path).isEmpty
        ? '.jpg'
        : p.extension(source.path);
    final dest = p.join(
      dir.path,
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}$ext',
    );
    await source.copy(dest);
    return dest;
  }

  /// Deletes every saved avatar and review photo (used by the demo reset).
  static Future<void> deletePhotos() async {
    for (final folder in const [
      avatarsDir,
      reviewPhotosDir,
      reactionPhotosDir,
    ]) {
      final base = _baseOf(folder);
      if (base == null) continue;
      try {
        final dir = Directory(p.join(base, folder));
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (e) {
        debugPrint('photo cleanup failed: $e');
      }
    }
  }

  /// Deletes one stored photo file; a missing file is fine.
  static Future<void> deleteFile(String? stored) async {
    final path = resolve(stored);
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// Path to keep in the database for a file inside one of the photo folders;
  /// any other path (for example a picker's temp file) is returned as is.
  static String? toStored(String? path) {
    if (path == null) return null;
    final folder = p.basename(p.dirname(path));
    if (!_photoFolders.contains(folder)) return path;
    return '$folder/${p.basename(path)}';
  }

  /// Real file path for a stored value (null stays null).
  static String? resolve(String? stored) {
    if (stored == null) return null;
    final folder = p.basename(p.dirname(stored));
    final base = _baseOf(folder);
    if (base == null) return stored;
    final current = p.join(base, folder, p.basename(stored));
    if (!p.isAbsolute(stored)) return current;
    // an old absolute path: keep it while it still works, else rebuild it
    return File(stored).existsSync() ? stored : current;
  }
}
