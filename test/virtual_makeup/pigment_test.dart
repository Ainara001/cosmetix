import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';

import 'package:cosmetix/features/virtual_makeup/domain/face_quality.dart';
import 'package:cosmetix/features/virtual_makeup/domain/makeup_look.dart';
import 'package:cosmetix/features/virtual_makeup/engine/color_math.dart';
import 'package:cosmetix/features/virtual_makeup/engine/makeup_backend.dart';
import 'package:cosmetix/features/virtual_makeup/engine/pigment_backend.dart';
import 'package:cosmetix/features/virtual_makeup/engine/polygon_raster.dart';
import 'package:cosmetix/features/virtual_makeup/engine/protection_mask.dart';
import 'package:cosmetix/features/virtual_makeup/engine/rgba_image.dart';
import 'package:cosmetix/features/virtual_makeup/engine/zone_masks.dart';

import 'synthetic_face.dart';

/// The pigment engine on small, hand-made pictures where the right answer is
/// known. The pictures are TEST INPUTS (invented on purpose), not measurements.
const _backend = PigmentBackend();
const _off = ZoneLook(color: Color(0xFF000000), enabled: false);

/// A picture of one flat colour with a zone mask covering most of it.
({PreparedFace face, RgbaImage image}) _flat(
  int r,
  int g,
  int b, {
  int w = 60,
  int h = 40,
}) {
  final img = RgbaImage(w, h, Uint8List(w * h * 4));
  for (var i = 0; i < w * h; i++) {
    img.pixels[i * 4] = r;
    img.pixels[i * 4 + 1] = g;
    img.pixels[i * 4 + 2] = b;
    img.pixels[i * 4 + 3] = 255;
  }
  MaskPatch full() {
    final m = MaskPatch(5, 5, w - 10, h - 10);
    m.data.fillRange(0, m.data.length, 1);
    return m;
  }

  final synthetic = SyntheticFace.build();
  final face = PreparedFace(
    image: img,
    points: synthetic.points,
    masks: ZoneMasks(
      lips: full(),
      eyeshadow: MaskPatch(0, 0, 0, 0),
      blush: MaskPatch(0, 0, 0, 0),
      skin: MaskPatch(0, 0, w, h),
    ),
    quality: FaceQuality.assess(synthetic.points, w),
  );
  return (face: face, image: img);
}

Lab _at(RgbaImage i, int x, int y) {
  final o = (y * i.width + x) * 4;
  return ColorMath.rgbToLab(i.pixels[o], i.pixels[o + 1], i.pixels[o + 2]);
}

RgbaImage _lips(PreparedFace f, Color c, {double k = 1, double? opacity}) =>
    _backend.renderSync(
      MakeupRequest(
        face: f,
        look: MakeupLook(
          lips: ZoneLook(color: c, intensity: k, opacity: opacity),
          eyeshadow: _off,
          blush: _off,
        ),
      ),
    );

void main() {
  test('the mean colour after the makeup is the LINEAR-LIGHT mix', () {
    final t = _flat(200, 140, 120);
    const pig = Color(0xFF8A1F3A);
    final out = _lips(t.face, pig, opacity: 0.6);
    // expected: (1 - 0.6) * base + 0.6 * pigment, per channel in linear light
    double lin(int v) => ColorMath.srgbByteToLinear(v);
    double mix(int base, double pigment) =>
        0.4 * lin(base) + 0.6 * ColorMath.srgbToLinear(pigment);
    final want = [
      ColorMath.linearToSrgbByte(mix(200, pig.r)),
      ColorMath.linearToSrgbByte(mix(140, pig.g)),
      ColorMath.linearToSrgbByte(mix(120, pig.b)),
    ];
    final o = (20 * out.width + 30) * 4;
    for (var c = 0; c < 3; c++) {
      expect(out.pixels[o + c], closeTo(want[c], 1), reason: 'channel $c');
    }
  });

  test(
    'a cool pink over warm skin gives a colour BETWEEN them, never colder',
    () {
      // the lilac cheeks of the first engine: a pale cool pink on warm skin
      final t = _flat(222, 170, 140); // warm skin
      const pink = Color(0xFFDDB1B6); // cool, pale pink
      final skin = _at(t.image, 30, 20);
      final pigLab = ColorMath.colorToLab(pink);
      final res = _at(_lips(t.face, pink, k: 1, opacity: 0.6), 30, 20);
      // b* (yellow-blue): between the skin and the pigment
      expect(res.b, lessThan(skin.b));
      expect(res.b, greaterThan(pigLab.b));
      // and the hue turns toward the pigment, not past it
      double hue(Lab c) => math.atan2(c.b, c.a);
      expect(hue(res), greaterThan(math.min(hue(skin), hue(pigLab)) - 0.02));
      expect(hue(res), lessThan(math.max(hue(skin), hue(pigLab)) + 0.02));
    },
  );

  test('a very dark pixel stays dark and keeps its hue (no blue line)', () {
    // red lips with a dark line between them, lipstick of a cool pink
    final t = _flat(190, 40, 50);
    final o = (20 * 60 + 30) * 4;
    t.image.pixels[o] = 24;
    t.image.pixels[o + 1] = 6;
    t.image.pixels[o + 2] = 8; // a dark red-black pixel
    final out = _lips(t.face, const Color(0xFFE8869A));
    final before = _at(t.image, 30, 20), after = _at(out, 30, 20);
    expect(after.l, lessThan(30), reason: 'stays dark');
    expect(after.b, greaterThan(-3), reason: 'did not turn blue');
    expect(after.a, greaterThan(0), reason: 'still on the red side');
    expect(before.l, lessThan(15));
  });

  test('a white nail or tooth under the mask is not painted', () {
    final t = _flat(190, 40, 50);
    // a small white patch inside the lips
    for (var y = 15; y < 21; y++) {
      for (var x = 25; x < 33; x++) {
        final o = (y * 60 + x) * 4;
        t.image.pixels[o] = 240;
        t.image.pixels[o + 1] = 236;
        t.image.pixels[o + 2] = 228;
      }
    }
    // the cached zone data must be learned from THIS picture
    final fresh = PreparedFace(
      image: t.image,
      points: t.face.points,
      masks: t.face.masks,
      quality: t.face.quality,
    );
    final out = _lips(fresh, const Color(0xFFB03A48));
    int diff(int x, int y) {
      final o = (y * 60 + x) * 4;
      return (out.pixels[o] - t.image.pixels[o]).abs() +
          (out.pixels[o + 1] - t.image.pixels[o + 1]).abs() +
          (out.pixels[o + 2] - t.image.pixels[o + 2]).abs();
    }

    expect(diff(28, 18), lessThan(15), reason: 'the white patch stays white');
    expect(diff(10, 10), greaterThan(40), reason: 'the lips are painted');
  });

  test('a highlight stays a highlight', () {
    final t = _flat(190, 40, 50);
    for (var y = 18; y < 21; y++) {
      for (var x = 28; x < 32; x++) {
        final o = (y * 60 + x) * 4;
        t.image.pixels[o] = 255;
        t.image.pixels[o + 1] = 250;
        t.image.pixels[o + 2] = 250;
      }
    }
    final fresh = PreparedFace(
      image: t.image,
      points: t.face.points,
      masks: t.face.masks,
      quality: t.face.quality,
    );
    final out = _lips(fresh, const Color(0xFFB03A48));
    final o = (19 * 60 + 29) * 4;
    final chroma = (out.pixels[o] - out.pixels[o + 2]).abs();
    expect(chroma, lessThan(20), reason: 'still nearly white');
  });

  test('a lower opacity changes less; opacity 0 changes nothing', () {
    final t = _flat(200, 140, 120);
    int change(RgbaImage i) {
      var s = 0;
      for (var k = 0; k < i.pixels.length; k++) {
        if (k % 4 == 3) continue;
        s += (i.pixels[k] - t.image.pixels[k]).abs();
      }
      return s;
    }

    const c = Color(0xFF8A1F3A);
    final full = change(_lips(t.face, c, opacity: 1));
    final half = change(_lips(t.face, c, opacity: 0.5));
    final none = change(_lips(t.face, c, opacity: 0));
    expect(none, 0);
    expect(half, lessThan(full));
    expect(half, greaterThan(0));
  });

  test('two zones on the same pixels act together (gains multiply)', () {
    final t = _flat(200, 140, 120);
    final both = ZoneMasks(
      lips: t.face.masks.lips,
      eyeshadow: t.face.masks.lips, // the same area on purpose
      blush: MaskPatch(0, 0, 0, 0),
      skin: t.face.masks.skin,
    );
    final face = PreparedFace(
      image: t.image,
      points: t.face.points,
      masks: both,
      quality: t.face.quality,
    );
    const a = Color(0xFFB03A48), b = Color(0xFF3A6AB0);
    RgbaImage render(ZoneLook l, ZoneLook e) => _backend.renderSync(
      MakeupRequest(
        face: face,
        look: MakeupLook(lips: l, eyeshadow: e, blush: _off),
      ),
    );
    final onlyA = render(const ZoneLook(color: a, intensity: 1), _off);
    final onlyB = render(_off, const ZoneLook(color: b, intensity: 1));
    final both2 = render(
      const ZoneLook(color: a, intensity: 1),
      const ZoneLook(color: b, intensity: 1),
    );
    final la = _at(onlyA, 30, 20), lb = _at(onlyB, 30, 20);
    final lab = _at(both2, 30, 20);
    expect(ColorMath.deltaE2000(lab, la), greaterThan(3));
    expect(ColorMath.deltaE2000(lab, lb), greaterThan(3));
  });

  test(
    'protection and the outside of the zones are returned byte for byte',
    () {
      final t = _flat(200, 140, 120);
      final prot = ProtectionMask(60, 40);
      prot.dab(30, 20, 5, hardness: 1);
      final out = _backend.renderSync(
        MakeupRequest(
          face: t.face,
          look: const MakeupLook(
            lips: ZoneLook(color: Color(0xFFB03A48), intensity: 1),
            eyeshadow: _off,
            blush: _off,
          ),
          protection: prot,
        ),
      );
      for (var y = 0; y < 40; y++) {
        for (var x = 0; x < 60; x++) {
          final o = (y * 60 + x) * 4;
          final outside = x < 5 || x >= 55 || y < 5 || y >= 35;
          if (outside || prot.at(x, y) >= 1) {
            expect(
              out.pixels.sublist(o, o + 3),
              orderedEquals(t.image.pixels.sublist(o, o + 3)),
              reason: 'pixel $x,$y',
            );
          }
        }
      }
    },
  );

  test('redness inside the skin zone is still redness after the makeup', () {
    // a blush over skin with a red spot: its colour contrast to the skin around
    // is kept (the skin zones keep the variation of colour in full)
    final t = _flat(215, 160, 135);
    for (var y = 19; y < 22; y++) {
      for (var x = 29; x < 32; x++) {
        final o = (y * 60 + x) * 4;
        t.image.pixels[o] = 225;
        t.image.pixels[o + 1] = 120;
        t.image.pixels[o + 2] = 110;
      }
    }
    final face = PreparedFace(
      image: t.image,
      points: t.face.points,
      masks: ZoneMasks(
        lips: MaskPatch(0, 0, 0, 0),
        eyeshadow: MaskPatch(0, 0, 0, 0),
        blush: t.face.masks.lips, // the flat full mask
        skin: t.face.masks.skin,
      ),
      quality: t.face.quality,
    );
    final out = _backend.renderSync(
      MakeupRequest(
        face: face,
        look: const MakeupLook(
          lips: _off,
          eyeshadow: _off,
          blush: ZoneLook(color: Color(0xFFE08A8A), intensity: 0.6),
        ),
      ),
    );
    double spot(RgbaImage i) => _at(i, 30, 20).a - _at(i, 20, 20).a;
    expect(spot(t.image), greaterThan(5));
    // measured on this picture: about 78 % of the a* contrast is left (the zone
    // moves to a paler pink, where the same ratio is a smaller a* difference)
    expect(spot(out), greaterThan(spot(t.image) * 0.7));
    // the red-to-green RATIO between the spot and the skin stays (within a few
    // per cent: the gate lets a clear colour outlier take slightly less paint)
    double ratio(RgbaImage i, int x, int y) {
      final o = (y * i.width + x) * 4;
      return ColorMath.srgbByteToLinear(i.pixels[o]) /
          ColorMath.srgbByteToLinear(i.pixels[o + 1]);
    }

    final before = ratio(t.image, 30, 20) / ratio(t.image, 20, 20);
    final after = ratio(out, 30, 20) / ratio(out, 20, 20);
    expect(after, closeTo(before, before * 0.12));
  });

  group('stage 7 regressions', () {
    double chroma(Lab c) => math.sqrt(c.a * c.a + c.b * c.b);

    PreparedFace withZone(PreparedFace f, MakeupZone zone) => PreparedFace(
      image: f.image,
      points: f.points,
      masks: ZoneMasks(
        lips: zone == MakeupZone.lips ? f.masks.lips : MaskPatch(0, 0, 0, 0),
        eyeshadow: zone == MakeupZone.eyeshadow
            ? f.masks.lips
            : MaskPatch(0, 0, 0, 0),
        blush: zone == MakeupZone.blush ? f.masks.lips : MaskPatch(0, 0, 0, 0),
        skin: f.masks.skin,
      ),
      quality: f.quality,
    );

    RgbaImage render(
      PreparedFace f,
      MakeupZone zone,
      Color color, {
      double k = 1,
    }) => _backend.renderSync(
      MakeupRequest(
        face: f,
        look: MakeupLook(
          lips: zone == MakeupZone.lips
              ? ZoneLook(color: color, intensity: k)
              : _off,
          eyeshadow: zone == MakeupZone.eyeshadow
              ? ZoneLook(color: color, intensity: k)
              : _off,
          blush: zone == MakeupZone.blush
              ? ZoneLook(color: color, intensity: k)
              : _off,
        ),
      ),
    );

    test('a shadowed upper lip takes the lipstick colour, not grey', () {
      final t = _flat(180, 60, 55); // red lips
      // the upper lip is in shadow: darker and less saturated
      for (var y = 5; y < 22; y++) {
        for (var x = 5; x < 55; x++) {
          final o = (y * 60 + x) * 4;
          t.image.pixels[o] = 105;
          t.image.pixels[o + 1] = 80;
          t.image.pixels[o + 2] = 78;
        }
      }
      final fresh = withZone(t.face, MakeupZone.lips);
      final out = render(fresh, MakeupZone.lips, const Color(0xFFC2185B));
      final before = _at(t.image, 30, 10); // in the shadowed upper lip
      final after = _at(out, 30, 10);
      final lower = _at(out, 30, 28); // the normal lower lip
      expect(
        chroma(after),
        greaterThan(chroma(before)),
        reason: 'gains colour',
      );
      expect(chroma(after), greaterThan(8), reason: 'does not turn grey');
      expect(after.l, lessThan(lower.l), reason: 'the shadow is kept');
    });

    test('dark spots near the mouth keep their hue under blush', () {
      final t = _flat(215, 160, 135); // skin
      // a dark spot (a mole) near the mouth
      for (var y = 20; y < 23; y++) {
        for (var x = 28; x < 31; x++) {
          final o = (y * 60 + x) * 4;
          t.image.pixels[o] = 90;
          t.image.pixels[o + 1] = 55;
          t.image.pixels[o + 2] = 50;
        }
      }
      final face = withZone(t.face, MakeupZone.blush);
      final out = render(
        face,
        MakeupZone.blush,
        const Color(0xFFE08A8A),
        k: 0.6,
      );
      final after = _at(out, 29, 21);
      final around = _at(out, 20, 21);
      expect(after.l, lessThan(around.l), reason: 'the spot stays dark');
      expect(after.a, greaterThan(0), reason: 'still on the red side');
      expect(after.b, greaterThan(-4), reason: 'did not turn blue');
    });

    test('a saturated eyeshadow reads on dark skin at full intensity', () {
      final t = _flat(80, 55, 45); // dark brown skin
      final face = withZone(t.face, MakeupZone.eyeshadow);
      final out = render(face, MakeupZone.eyeshadow, const Color(0xFF6A1B9A));
      final before = _at(t.image, 30, 20);
      final after = _at(out, 30, 20);
      expect(
        chroma(after),
        greaterThan(chroma(before) * 3),
        reason: 'shows up',
      );
      expect(after.a, greaterThan(8), reason: 'purple a*');
      expect(after.b, lessThan(-4), reason: 'purple b*');
    });
  });
}
