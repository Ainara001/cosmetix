import 'dart:typed_data';

/// A picture as straight RGBA bytes (4 bytes per pixel, row after row). The
/// engine works on this plain type, so it does not depend on the UI.
class RgbaImage {
  RgbaImage(this.width, this.height, this.pixels)
    : assert(pixels.length >= width * height * 4);

  factory RgbaImage.blank(int width, int height) =>
      RgbaImage(width, height, Uint8List(width * height * 4));

  final int width;
  final int height;
  final Uint8List pixels;

  RgbaImage copy() => RgbaImage(width, height, Uint8List.fromList(pixels));
}
