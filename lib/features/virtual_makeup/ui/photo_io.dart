import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../engine/rgba_image.dart';

/// Where the photo comes from. The photo is kept in memory only: it is not
/// saved, not sent anywhere, and the temporary copy is deleted.
abstract interface class MakeupPhotoSource {
  /// Null when the user cancelled.
  Future<Uint8List?> pick({required bool camera});
}

class ImagePickerMakeupPhotoSource implements MakeupPhotoSource {
  const ImagePickerMakeupPhotoSource();

  @override
  Future<Uint8List?> pick({required bool camera}) async {
    final x = await ImagePicker().pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 92,
    );
    if (x == null) return null;
    final bytes = await x.readAsBytes();
    try {
      // only the picker's own temporary copy, never the user's file
      if (isInsideAny(x.path, await tempRoots())) {
        final f = File(x.path);
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}
    return bytes;
  }

  /// The folders where the picker puts its copies. On Android that is the cache
  /// folder (= `getTemporaryDirectory`); on iOS it is `NSTemporaryDirectory`
  /// (= `Directory.systemTemp`), which is NOT the folder `getTemporaryDirectory`
  /// returns there (that one is Caches). Both are the app's own folders.
  @visibleForTesting
  static Future<List<String>> tempRoots() async => [
    (await getTemporaryDirectory()).path,
    Directory.systemTemp.path,
  ];

  /// True when [path] lies strictly inside one of [roots].
  @visibleForTesting
  static bool isInsideAny(String path, Iterable<String> roots) => roots.any(
    (r) => r.isNotEmpty && p.isWithin(p.normalize(r), p.normalize(path)),
  );
}

class PhotoDecoder {
  PhotoDecoder._();

  /// Decodes [bytes] to RGBA with the long side at most [maxSide] pixels. The
  /// engine's decoder applies the EXIF rotation and reports the turned size;
  /// `photo_decode_test.dart` checks that for orientations 1, 6 and 8 on the
  /// test engine (not yet on a phone). Throws when it is not a picture.
  static Future<RgbaImage> decode(Uint8List bytes, {int maxSide = 1280}) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      final w = descriptor.width, h = descriptor.height;
      final scale = (w > h ? w : h) > maxSide ? maxSide / (w > h ? w : h) : 1.0;
      final codec = await descriptor.instantiateCodec(
        targetWidth: (w * scale).round(),
        targetHeight: (h * scale).round(),
      );
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final out = RgbaImage(
        frame.image.width,
        frame.image.height,
        Uint8List.fromList(data!.buffer.asUint8List()),
      );
      frame.image.dispose();
      codec.dispose();
      return out;
    } finally {
      descriptor.dispose();
      buffer.dispose();
    }
  }

  /// RGBA pixels to a picture the UI can draw.
  static Future<ui.Image> toUiImage(RgbaImage image) {
    final completer = ui.ImmutableBuffer.fromUint8List(image.pixels).then((
      buffer,
    ) async {
      final desc = ui.ImageDescriptor.raw(
        buffer,
        width: image.width,
        height: image.height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final codec = await desc.instantiateCodec();
      final frame = await codec.getNextFrame();
      desc.dispose();
      buffer.dispose();
      codec.dispose();
      return frame.image;
    });
    return completer;
  }
}
