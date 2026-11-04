import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image_picker/image_picker.dart';

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
      final f = File(x.path);
      // only the temporary copy of the picker, never the user's own file
      if (x.path.contains('/tmp/') ||
          x.path.contains('/cache/') ||
          x.path.contains('/Caches/') ||
          x.path.contains('image_picker')) {
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}
    return bytes;
  }
}

class PhotoDecoder {
  PhotoDecoder._();

  /// Decodes [bytes] to RGBA with the long side at most [maxSide] pixels (the
  /// EXIF rotation is applied by the decoder). Throws when it is not a picture.
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
