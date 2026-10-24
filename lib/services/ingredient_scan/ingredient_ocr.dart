import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// Text recognition is not possible (no OCR on this platform, or it failed).
/// The scanner then offers typing the ingredients by hand.
class OcrUnavailable implements Exception {
  const OcrUnavailable(this.message);
  final String message;

  @override
  String toString() => 'OcrUnavailable: $message';
}

/// Reads the text of a photo. Always on the phone: the photo is never sent
/// anywhere.
abstract class IngredientOcr {
  /// Recognized text, lines separated by "\n" (may be empty when nothing was
  /// readable). Throws [OcrUnavailable].
  Future<String> recognize(String imagePath);
}

/// Apple Vision on iOS, through the `cosmetix/ocr` platform channel
/// (see `ios/Runner/AppDelegate.swift`).
class PlatformIngredientOcr implements IngredientOcr {
  const PlatformIngredientOcr();

  static const _channel = MethodChannel('cosmetix/ocr');

  @override
  Future<String> recognize(String imagePath) async {
    if (!Platform.isIOS) {
      throw const OcrUnavailable('Text recognition is available on iOS only');
    }
    try {
      final text = await _channel.invokeMethod<String>('recognizeText', {
        'path': imagePath,
      });
      return text ?? '';
    } on MissingPluginException {
      throw const OcrUnavailable('Text recognition is not installed');
    } on PlatformException catch (e) {
      throw OcrUnavailable(e.message ?? 'Text recognition failed');
    }
  }
}

/// Where the scanner gets the photo from. The gallery works everywhere,
/// including the iOS Simulator; the camera needs a real device.
abstract class ScanPhotoSource {
  /// Path of the picked image, or null when the user cancelled.
  /// Throws [PhotoUnavailable] when the camera / gallery can not be used.
  Future<String?> pick({required bool camera});
}

class PhotoUnavailable implements Exception {
  const PhotoUnavailable(this.message);
  final String message;

  @override
  String toString() => 'PhotoUnavailable: $message';
}

class ImagePickerPhotoSource implements ScanPhotoSource {
  const ImagePickerPhotoSource();

  @override
  Future<String?> pick({required bool camera}) async {
    try {
      final x = await ImagePicker().pickImage(
        source: camera ? ImageSource.camera : ImageSource.gallery,
        // labels have small print: keep more pixels than for selfies
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 90,
      );
      return x?.path;
    } on PlatformException catch (e) {
      throw PhotoUnavailable(e.message ?? e.code);
    } catch (e) {
      throw PhotoUnavailable('$e');
    }
  }
}
