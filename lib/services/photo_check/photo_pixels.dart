import 'dart:typed_data';
import 'dart:ui' as ui;

/// A decoded photo: RGBA, 8 bits per channel, row after row. Own class on
/// purpose: the photo check does not depend on any other feature's types.
class PhotoPixels {
  PhotoPixels(this.width, this.height, this.rgba)
    : assert(rgba.length == width * height * 4);

  final int width;
  final int height;
  final Uint8List rgba;

  /// Decodes [bytes] with the long side at most [maxSide] pixels.
  ///
  /// The engine's decoder applies the EXIF orientation, so a photo taken with a
  /// turned phone comes out upright (tested in `integration_test/photo_check_*`
  /// with orientations 1, 6 and 3 on the simulator). Throws [FormatException]
  /// for anything that is not a readable picture: a corrupt, truncated or empty file.
  static Future<PhotoPixels> decode(
    Uint8List bytes, {
    int maxSide = 2048,
  }) async {
    if (bytes.isEmpty) throw const FormatException('empty file');
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final w = descriptor.width, h = descriptor.height;
      if (w < 8 || h < 8) throw const FormatException('picture too small');
      final long = w > h ? w : h;
      final scale = long > maxSide ? maxSide / long : 1.0;
      codec = await descriptor.instantiateCodec(
        targetWidth: (w * scale).round(),
        targetHeight: (h * scale).round(),
      );
      final frame = await codec.getNextFrame();
      image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw const FormatException('no pixel data');
      return PhotoPixels(
        image.width,
        image.height,
        Uint8List.fromList(data.buffer.asUint8List()),
      );
    } catch (e) {
      if (e is FormatException) rethrow;
      // the engine reports a bad file as a plain Exception/StateError: one error type for callers
      throw FormatException('cannot decode the picture: $e');
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}
