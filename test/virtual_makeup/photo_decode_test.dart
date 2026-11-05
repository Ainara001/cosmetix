import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:cosmetix/features/virtual_makeup/engine/rgba_image.dart';
import 'package:cosmetix/features/virtual_makeup/ui/photo_io.dart';
import 'package:flutter_test/flutter_test.dart';

/// Photos from a phone are often stored sideways with an EXIF "orientation"
/// tag. These pictures are made from ONE raw picture (60x40: red top-left,
/// green top-right, blue bottom-left, yellow bottom-right) that only differ in
/// that tag, so the decoder is checked against what the tag says:
///   1 = as stored, 6 = show turned 90 degrees clockwise, 8 = counter-clockwise.
/// This runs on the test engine; a phone decoder is not covered by it.
const _red = Color(0xFFDC1E1E);
const _green = Color(0xFF1EC829);
const _blue = Color(0xFF1E3CDC);
const _yellow = Color(0xFFE6D11E);

Future<RgbaImage> _decode(String name, {int maxSide = 1280}) async {
  late RgbaImage out;
  final bytes = File('test/virtual_makeup/fixtures/$name').readAsBytesSync();
  await TestWidgetsFlutterBinding.ensureInitialized().runAsync(() async {
    out = await PhotoDecoder.decode(bytes, maxSide: maxSide);
  });
  return out;
}

/// The colour a quarter of the way in from a corner (JPEG blurs the borders).
List<int> _at(RgbaImage i, double fx, double fy) {
  final o = ((i.height * fy).floor() * i.width + (i.width * fx).floor()) * 4;
  return [i.pixels[o], i.pixels[o + 1], i.pixels[o + 2]];
}

Matcher _is(Color c) => predicate<List<int>>(
  (v) =>
      (v[0] - (c.r * 255).round()).abs() < 12 &&
      (v[1] - (c.g * 255).round()).abs() < 12 &&
      (v[2] - (c.b * 255).round()).abs() < 12,
  'is about $c',
);

void _expectCorners(RgbaImage i, Color tl, Color tr, Color bl, Color br) {
  expect(_at(i, .25, .25), _is(tl), reason: 'top-left');
  expect(_at(i, .75, .25), _is(tr), reason: 'top-right');
  expect(_at(i, .25, .75), _is(bl), reason: 'bottom-left');
  expect(_at(i, .75, .75), _is(br), reason: 'bottom-right');
}

void main() {
  test('orientation 1: as stored', () async {
    final i = await _decode('quadrants_exif1.jpg');
    expect((i.width, i.height), (60, 40));
    _expectCorners(i, _red, _green, _blue, _yellow);
  });

  test(
    'orientation 6: turned clockwise, and the size is the turned size',
    () async {
      final i = await _decode('quadrants_exif6.jpg');
      expect((i.width, i.height), (40, 60));
      _expectCorners(i, _blue, _red, _yellow, _green);
    },
  );

  test('orientation 8: turned counter-clockwise', () async {
    final i = await _decode('quadrants_exif8.jpg');
    expect((i.width, i.height), (40, 60));
    _expectCorners(i, _green, _yellow, _red, _blue);
  });

  test('a large sideways photo is turned first and then shrunk', () async {
    // stored 1600x1000, shown 1000x1600; the long side becomes 1280
    final i = await _decode('big_1600x1000_exif6.jpg');
    expect((i.width, i.height), (800, 1280));
    _expectCorners(i, _blue, _red, _yellow, _green);
  });

  test('bytes that are not a picture throw', () async {
    await TestWidgetsFlutterBinding.ensureInitialized().runAsync(() async {
      await expectLater(
        PhotoDecoder.decode(Uint8List.fromList([1, 2, 3, 4])),
        throwsA(anything),
      );
    });
  });

  group('which picked files may be deleted', () {
    const roots = ['/var/mobile/App/tmp', '/var/mobile/App/Library/Caches'];
    bool inside(String p) => ImagePickerMakeupPhotoSource.isInsideAny(p, roots);

    test('the picker copies in the app temporary folders are', () {
      expect(inside('/var/mobile/App/tmp/image_picker_ABC.jpg'), isTrue);
      expect(inside('/var/mobile/App/Library/Caches/x/y.jpg'), isTrue);
    });

    test(
      'the user\'s own files are not, even with tmp or cache in the name',
      () {
        expect(inside('/Users/me/Pictures/tmp/photo.jpg'), isFalse);
        expect(inside('/Users/me/Documents/image_picker_notes.jpg'), isFalse);
        expect(inside('/var/mobile/App/tmp2/photo.jpg'), isFalse);
        expect(inside('/var/mobile/App/Documents/photo.jpg'), isFalse);
        expect(inside('/var/mobile/App/tmp/../Documents/photo.jpg'), isFalse);
      },
    );

    test('the folder itself and an empty root are not', () {
      expect(inside('/var/mobile/App/tmp'), isFalse);
      expect(
        ImagePickerMakeupPhotoSource.isInsideAny('/a/b.jpg', const ['']),
        isFalse,
      );
    });
  });
}
