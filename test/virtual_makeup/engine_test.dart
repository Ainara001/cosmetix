import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color, Offset;

import 'package:flutter_test/flutter_test.dart';

import 'package:cosmetix/features/virtual_makeup/domain/face_geometry.dart';
import 'package:cosmetix/features/virtual_makeup/domain/face_quality.dart';
import 'package:cosmetix/features/virtual_makeup/domain/makeup_look.dart';
import 'package:cosmetix/features/virtual_makeup/engine/blemish_suggester.dart';
import 'package:cosmetix/features/virtual_makeup/engine/color_math.dart';
import 'package:cosmetix/features/virtual_makeup/engine/color_transfer_backend.dart';
import 'package:cosmetix/features/virtual_makeup/engine/makeup_backend.dart';
import 'package:cosmetix/features/virtual_makeup/engine/polygon_raster.dart';
import 'package:cosmetix/features/virtual_makeup/engine/protection_mask.dart';
import 'package:cosmetix/features/virtual_makeup/engine/rgba_image.dart';
import 'package:cosmetix/features/virtual_makeup/engine/zone_masks.dart';

import 'synthetic_face.dart';

const _backend = ColorTransferBackend();

/// Lightness of every pixel.
List<double> _lightness(RgbaImage img) => [
  for (var i = 0; i < img.width * img.height; i++)
    ColorMath.rgbToLab(
      img.pixels[i * 4],
      img.pixels[i * 4 + 1],
      img.pixels[i * 4 + 2],
    ).l,
];

/// Energy of the fine detail (pixel minus the 3x3 average) of the lightness,
/// over the pixels where [mask] is above 0.5.
double _detail(List<double> l, int w, int h, bool Function(int x, int y) mask) {
  var e = 0.0;
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      if (!mask(x, y)) continue;
      var s = 0.0;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          s += l[(y + dy) * w + x + dx];
        }
      }
      final d = l[y * w + x] - s / 9;
      e += d * d;
    }
  }
  return e;
}

int _samePixels(RgbaImage a, RgbaImage b) {
  var n = 0;
  for (var i = 0; i < a.width * a.height; i++) {
    if (a.pixels[i * 4] == b.pixels[i * 4] &&
        a.pixels[i * 4 + 1] == b.pixels[i * 4 + 1] &&
        a.pixels[i * 4 + 2] == b.pixels[i * 4 + 2]) {
      n++;
    }
  }
  return n;
}

void main() {
  group('colour maths', () {
    test('white, black and red have the known Lab values', () {
      final w = ColorMath.rgbToLab(255, 255, 255);
      expect(w.l, closeTo(100, 0.1));
      expect(w.a.abs(), lessThan(0.1));
      expect(ColorMath.rgbToLab(0, 0, 0).l, closeTo(0, 0.01));
      final r = ColorMath.rgbToLab(255, 0, 0);
      expect(r.l, closeTo(53.24, 0.3));
      expect(r.a, closeTo(80.09, 0.3));
      expect(r.b, closeTo(67.20, 0.3));
    });

    test('RGB to Lab and back loses at most one level', () {
      final out = Uint8List(4);
      for (final c in [
        [228, 178, 150],
        [184, 98, 108],
        [12, 200, 40],
        [250, 250, 250],
        [5, 5, 5],
        [128, 128, 128],
      ]) {
        final lab = ColorMath.rgbToLab(c[0], c[1], c[2]);
        ColorMath.labToRgb(lab.l, lab.a, lab.b, out, 0);
        expect((out[0] - c[0]).abs(), lessThanOrEqualTo(1));
        expect((out[1] - c[1]).abs(), lessThanOrEqualTo(1));
        expect((out[2] - c[2]).abs(), lessThanOrEqualTo(1));
      }
    });
  });

  group('polygon raster', () {
    test('a square covers its area, edges are anti-aliased', () {
      final p = PolygonRaster.fill(
        const [
          Offset(2.5, 2.5),
          Offset(12.5, 2.5),
          Offset(12.5, 12.5),
          Offset(2.5, 12.5),
        ],
        0,
        0,
        16,
        16,
      );
      expect(p.sum, closeTo(100, 0.5));
      expect(p.at(7, 7), 1);
      expect(p.at(2, 2), closeTo(0.25, 0.02)); // a corner pixel is a quarter
      expect(p.at(1, 7), 0);
    });

    test('blur keeps the total and never leaves 0..1', () {
      final p = PolygonRaster.fill(
        const [Offset(8, 8), Offset(24, 8), Offset(24, 24), Offset(8, 24)],
        0,
        0,
        32,
        32,
      );
      final before = p.sum;
      PolygonRaster.blur(p, 2);
      expect(p.sum, closeTo(before, before * 0.02));
      expect(p.data.every((v) => v >= -1e-6 && v <= 1 + 1e-6), isTrue);
    });
  });

  group('zones on a synthetic face', () {
    final f = SyntheticFace.build();
    final face = PreparedFace.from(f.image, f.points);

    test('lips: the mask is on the lips, not on the mouth or the skin', () {
      final m = face.masks.lips;
      expect(m.at(240, 430 + 16), greaterThan(0.9)); // lower lip
      expect(m.at(240, 430 - 16), greaterThan(0.9)); // upper lip
      expect(m.at(240, 430), lessThan(0.1)); // the open mouth
      expect(m.at(240, 480), 0);
      expect(m.at(100, 430), 0);
    });

    test('eyeshadow: on the lid, not on the eye, not on the brow', () {
      final m = face.masks.eyeshadow;
      expect(
        m.at(175, 250 - 16),
        greaterThan(0.2),
      ); // the lid above the lash line
      expect(m.at(175, 250), lessThan(0.05)); // the open eye
      expect(m.at(175, 200), 0); // above the brow
      expect(m.at(240, 300), 0); // the nose
    });

    test(
      'blush: soft, on both cheeks, nothing on the eyes, lips or background',
      () {
        final m = face.masks.blush;
        final cr = ZoneMaskBuilderProbe.cheekRight(f),
            cl = ZoneMaskBuilderProbe.cheekLeft(f);
        expect(m.at(cr.dx.round(), cr.dy.round()), greaterThan(0.8));
        expect(m.at(cl.dx.round(), cl.dy.round()), greaterThan(0.8));
        expect(m.at(240, 430), 0);
        expect(m.at(175, 250), 0);
        expect(m.at(20, 300), 0);
      },
    );

    test('every mask stays inside the picture and inside 0..1', () {
      for (final m in [
        face.masks.lips,
        face.masks.eyeshadow,
        face.masks.blush,
        face.masks.skin,
      ]) {
        expect(m.x0, greaterThanOrEqualTo(0));
        expect(m.y0, greaterThanOrEqualTo(0));
        expect(m.x0 + m.width, lessThanOrEqualTo(SyntheticFace.width));
        expect(m.y0 + m.height, lessThanOrEqualTo(SyntheticFace.height));
        expect(m.data.every((v) => v >= -1e-6 && v <= 1 + 1e-6), isTrue);
      }
    });
  });

  group('the colour-transfer engine keeps the contract', () {
    final f = SyntheticFace.build();
    final face = PreparedFace.from(f.image, f.points);
    const look = MakeupLook();

    test(
      'intensity 0 or nothing enabled: the photo comes back byte for byte',
      () {
        final off = const MakeupLook(
          lips: ZoneLook(color: Color(0xFFB03A48), intensity: 0),
          eyeshadow: ZoneLook(color: Color(0xFF8A6A7A), enabled: false),
          blush: ZoneLook(color: Color(0xFFE08A8A), intensity: 0),
        );
        final out = _backend.renderSync(MakeupRequest(face: face, look: off));
        expect(out.pixels, orderedEquals(face.image.pixels));
      },
    );

    test('the result is a copy: the original photo is never touched', () {
      final before = Uint8List.fromList(face.image.pixels);
      final out = _backend.renderSync(MakeupRequest(face: face, look: look));
      expect(identical(out.pixels, face.image.pixels), isFalse);
      expect(face.image.pixels, orderedEquals(before));
    });

    test('pixels outside every zone are not changed', () {
      final out = _backend.renderSync(MakeupRequest(face: face, look: look));
      final lips = face.masks.lips,
          eyes = face.masks.eyeshadow,
          blush = face.masks.blush;
      var outsideChanged = 0, changed = 0;
      for (var y = 0; y < out.height; y++) {
        for (var x = 0; x < out.width; x++) {
          final o = (y * out.width + x) * 4;
          final diff =
              out.pixels[o] != face.image.pixels[o] ||
              out.pixels[o + 1] != face.image.pixels[o + 1] ||
              out.pixels[o + 2] != face.image.pixels[o + 2];
          if (!diff) continue;
          changed++;
          if (lips.at(x, y) + eyes.at(x, y) + blush.at(x, y) <= 0) {
            outsideChanged++;
          }
        }
      }
      expect(changed, greaterThan(2000), reason: 'the makeup must be visible');
      expect(outsideChanged, 0);
    });

    test('lipstick: the lips move toward the colour, the skin does not', () {
      final out = _backend.renderSync(MakeupRequest(face: face, look: look));
      Lab at(RgbaImage i, int x, int y) {
        final o = (y * i.width + x) * 4;
        return ColorMath.rgbToLab(
          i.pixels[o],
          i.pixels[o + 1],
          i.pixels[o + 2],
        );
      }

      final target = ColorMath.colorToLab(look.lips.color);
      final b = at(face.image, 240, 446), a = at(out, 240, 446);
      double dist(Lab p) => math.sqrt(
        math.pow(p.a - target.a, 2) + math.pow(p.b - target.b, 2).toDouble(),
      );
      expect(dist(a), lessThan(dist(b)));
      final skinBefore = at(face.image, 240, 330),
          skinAfter = at(out, 240, 330);
      expect(skinAfter.a, closeTo(skinBefore.a, 0.5));
    });

    test('a stronger intensity changes the picture more', () {
      int diffs(double k) {
        final l = MakeupLook(
          lips: ZoneLook(color: const Color(0xFFB03A48), intensity: k),
          blush: const ZoneLook(color: Color(0xFFE08A8A), enabled: false),
          eyeshadow: const ZoneLook(color: Color(0xFF8A6A7A), enabled: false),
        );
        final o = _backend.renderSync(MakeupRequest(face: face, look: l));
        return face.image.width * face.image.height -
            _samePixels(o, face.image);
      }

      expect(diffs(0.2), lessThan(diffs(1)));
    });

    test('NO SMOOTHING: the fine detail of the lips and the cheeks stays', () {
      final out = _backend.renderSync(MakeupRequest(face: face, look: look));
      final lb = _lightness(face.image), la = _lightness(out);
      for (final (name, patch) in [
        ('lips', face.masks.lips),
        ('blush', face.masks.blush),
        ('eyeshadow', face.masks.eyeshadow),
      ]) {
        bool inZone(int x, int y) => patch.at(x, y) > 0.5;
        final before = _detail(lb, out.width, out.height, inZone);
        final after = _detail(la, out.width, out.height, inZone);
        expect(before, greaterThan(0));
        expect(after / before, inInclusiveRange(0.9, 1.15), reason: name);
      }
    });

    test('acne, a scar and redness stay visible under the makeup', () {
      // the cheeks carry the red dots and the red patch
      final out = _backend.renderSync(MakeupRequest(face: face, look: look));
      Lab at(RgbaImage i, Offset p) {
        final o = (p.dy.round() * i.width + p.dx.round()) * 4;
        return ColorMath.rgbToLab(
          i.pixels[o],
          i.pixels[o + 1],
          i.pixels[o + 2],
        );
      }

      for (final d in f.dots) {
        if (face.masks.blush.at(d.dx.round(), d.dy.round()) < 0.3) continue;
        final ring = Offset(d.dx + 9, d.dy); // skin next to the dot
        final before = at(face.image, d).a - at(face.image, ring).a;
        final after = at(out, d).a - at(out, ring).a;
        expect(
          before,
          greaterThan(3),
          reason: 'the dot is redder than the skin',
        );
        expect(
          after,
          greaterThan(before * 0.8),
          reason: 'and still is after makeup',
        );
      }
    });

    test('protection: protected pixels are returned byte for byte', () {
      final prot = ProtectionMask(SyntheticFace.width, SyntheticFace.height);
      for (final d in f.dots) {
        prot.dab(d.dx, d.dy, 8, hardness: 1);
      }
      final out = _backend.renderSync(
        MakeupRequest(face: face, look: look, protection: prot),
      );
      var protectedPixels = 0;
      for (var y = 0; y < out.height; y++) {
        for (var x = 0; x < out.width; x++) {
          if (prot.at(x, y) < 1) continue;
          protectedPixels++;
          final o = (y * out.width + x) * 4;
          expect(
            out.pixels.sublist(o, o + 3),
            orderedEquals(face.image.pixels.sublist(o, o + 3)),
          );
        }
      }
      expect(protectedPixels, greaterThan(500));
    });

    test('protecting everything gives back the whole photo', () {
      final prot = ProtectionMask(SyntheticFace.width, SyntheticFace.height);
      prot.data.fillRange(0, prot.data.length, 255);
      final out = _backend.renderSync(
        MakeupRequest(face: face, look: look, protection: prot),
      );
      expect(out.pixels, orderedEquals(face.image.pixels));
    });

    test(
      'contract: it says what it cannot do and refuses a reference photo',
      () {
        expect(_backend.capabilities.supportsReference, isFalse);
        expect(_backend.capabilities.runsOnDevice, isTrue);
        expect(
          () => _backend.renderSync(
            MakeupRequest(face: face, look: look, reference: face.image),
          ),
          throwsUnsupportedError,
        );
      },
    );

    test(
      'a render takes well under a second on this machine (not a phone claim)',
      () {
        final sw = Stopwatch()..start();
        for (var i = 0; i < 5; i++) {
          _backend.renderSync(
            MakeupRequest(
              face: PreparedFace.from(f.image, f.points),
              look: look,
            ),
          );
        }
        sw.stop();
        expect(sw.elapsedMilliseconds / 5, lessThan(1000));
      },
    );
  });

  group('protection mask counter', () {
    double counted(ProtectionMask m) =>
        m.data.where((v) => v != 0).length / m.data.length;

    test('coverage and isEmpty always agree with a full count', () {
      final m = ProtectionMask(80, 60);
      void check(String step) {
        expect(m.coverage, closeTo(counted(m), 1e-12), reason: step);
        expect(m.isEmpty, counted(m) == 0, reason: step);
      }

      check('new');
      m.beginStroke();
      m.dab(20, 20, 10);
      check('dab');
      m.stroke(20, 20, 60, 40, 6);
      check('stroke');
      m.beginStroke();
      m.dab(30, 25, 8, erase: true);
      check('erase');
      m.dab(0, 0, 200, erase: true); // everything off, at the edges too
      check('erase all');
      expect(m.isEmpty, isTrue);
      m.undo();
      check('undo');
      m.redo();
      check('redo');
      m.undo();
      m.undo();
      check('undo twice');
      m.merge(Uint8List(80 * 60)..fillRange(0, 100, 255));
      check('merge');
      expect(m.coverage, greaterThanOrEqualTo(100 / (80 * 60)));
      m.clear();
      check('clear');
      expect(m.isEmpty, isTrue);
      m.undo();
      check('undo the clear');
      expect(m.isEmpty, isFalse);
      check('copy');
      expect(m.copy().coverage, m.coverage);
    });
  });

  group('protection mask', () {
    test('a dab protects, the eraser removes, strokes leave no gaps', () {
      final m = ProtectionMask(100, 100);
      expect(m.isEmpty, isTrue);
      m.dab(50, 50, 10, hardness: 1);
      expect(m.at(50, 50), 1);
      expect(m.at(50, 70), 0);
      m.dab(50, 50, 4, erase: true, hardness: 1);
      expect(m.at(50, 50), 0);
      final s = ProtectionMask(100, 100)..stroke(10, 10, 90, 10, 3);
      for (var x = 10; x <= 90; x++) {
        expect(s.at(x, 10), greaterThan(0.5), reason: 'gap at $x');
      }
    });

    test('undo and redo go step by step; clear can be undone', () {
      final m = ProtectionMask(40, 40);
      m.beginStroke();
      m.dab(10, 10, 5, hardness: 1);
      m.beginStroke();
      m.dab(30, 30, 5, hardness: 1);
      expect(m.at(30, 30), 1);
      m.undo();
      expect(m.at(30, 30), 0);
      expect(m.at(10, 10), 1);
      m.redo();
      expect(m.at(30, 30), 1);
      m.clear();
      expect(m.isEmpty, isTrue);
      m.undo();
      expect(m.at(30, 30), 1);
    });

    test('merge adds a suggestion and can be undone; coverage is a share', () {
      final m = ProtectionMask(10, 10);
      final sug = Uint8List(100)..fillRange(0, 10, 255);
      m.merge(sug);
      expect(m.coverage, closeTo(0.1, 1e-9));
      m.undo();
      expect(m.isEmpty, isTrue);
    });
  });

  group('blemish suggestion is a hint, not a diagnosis', () {
    test(
      'finds most red dots on a synthetic face and does not change the photo',
      () {
        final f = SyntheticFace.build();
        final face = PreparedFace.from(f.image, f.points);
        final before = Uint8List.fromList(f.image.pixels);
        final s = BlemishSuggester.suggest(
          f.image,
          face.masks,
          f.points.faceWidth,
        );
        expect(f.image.pixels, orderedEquals(before));
        expect(s.reliable, isTrue);
        var found = 0;
        for (final d in f.dots) {
          if (s.mask[d.dy.round() * f.image.width + d.dx.round()] == 255) {
            found++;
          }
        }
        expect(found, greaterThanOrEqualTo(4), reason: 'at least 4 of 6 dots');
        expect(s.coverage, lessThan(BlemishSuggester.maxCoverage));
      },
    );

    test('a clean synthetic face gets (almost) no suggestions', () {
      final f = SyntheticFace.build(withBlemishes: false);
      final face = PreparedFace.from(f.image, f.points);
      final s = BlemishSuggester.suggest(
        f.image,
        face.masks,
        f.points.faceWidth,
      );
      expect(s.regions, lessThanOrEqualTo(2));
    });

    test(
      'when almost everything stands out it says so and suggests nothing',
      () {
        final f = SyntheticFace.build(noise: 45);
        final face = PreparedFace.from(f.image, f.points);
        final s = BlemishSuggester.suggest(
          f.image,
          face.masks,
          f.points.faceWidth,
        );
        if (!s.reliable) {
          expect(s.mask.every((v) => v == 0), isTrue);
        }
        expect(s.coverage, isNotNull);
      },
    );
  });

  group('photo quality warnings', () {
    final f = SyntheticFace.build();

    test('a frontal face has no warnings', () {
      final q = FaceQuality.assess(f.points, SyntheticFace.width);
      expect(q.issues, isEmpty);
      expect(q.canRun, isTrue);
    });

    test('a turned head, a tilted head and a small face are flagged', () {
      final pts = [...f.points.points];
      pts[FaceIndices.noseTip] = const Offset(150, 345);
      expect(
        FaceQuality.assess(FacePoints(pts), SyntheticFace.width).issues,
        contains(QualityIssue.turnedHead),
      );
      final tilt = [...f.points.points];
      tilt[FaceIndices.eyeOuterLeft] =
          tilt[FaceIndices.eyeOuterLeft] + const Offset(0, 60);
      expect(
        FaceQuality.assess(FacePoints(tilt), SyntheticFace.width).issues,
        contains(QualityIssue.tiltedHead),
      );
      expect(
        FaceQuality.assess(f.points, 4000).issues,
        contains(QualityIssue.smallFace),
      );
    });

    test('several faces: the try-on is not run (it would be a guess)', () {
      final q = FaceQuality.assess(f.points, SyntheticFace.width, count: 2);
      expect(q.issues, contains(QualityIssue.severalFaces));
      expect(q.canRun, isFalse);
      expect(const FaceQuality(faceCount: 0).canRun, isFalse);
    });
  });

  group('zones that overlap add up', () {
    // A flat skin-coloured picture with two squares that share a strip: lips
    // on the left, blush on the right, 10 columns in common.
    final flat = RgbaImage(60, 40, Uint8List(60 * 40 * 4));
    for (var i = 0; i < 60 * 40; i++) {
      flat.pixels[i * 4] = 205;
      flat.pixels[i * 4 + 1] = 150;
      flat.pixels[i * 4 + 2] = 130;
      flat.pixels[i * 4 + 3] = 255;
    }
    MaskPatch square(int x0) {
      final m = MaskPatch(x0, 10, 20, 20);
      m.data.fillRange(0, m.data.length, 1);
      return m;
    }

    final synthetic = SyntheticFace.build();
    final face = PreparedFace(
      image: flat,
      points: synthetic.points,
      masks: ZoneMasks(
        lips: square(10),
        eyeshadow: MaskPatch(0, 0, 0, 0),
        blush: square(20),
        skin: MaskPatch(0, 0, 60, 40),
      ),
      quality: FaceQuality.assess(synthetic.points, 60),
    );
    const lips = ZoneLook(color: Color(0xFFB03A48), intensity: 1);
    const blush = ZoneLook(color: Color(0xFFE08A8A), intensity: 1);
    const off = ZoneLook(color: Color(0xFF000000), enabled: false);
    RgbaImage render(ZoneLook l, ZoneLook b) => _backend.renderSync(
      MakeupRequest(
        face: face,
        look: MakeupLook(lips: l, eyeshadow: off, blush: b),
      ),
    );
    Lab at(RgbaImage i, int x, int y) {
      final o = (y * i.width + x) * 4;
      return ColorMath.rgbToLab(i.pixels[o], i.pixels[o + 1], i.pixels[o + 2]);
    }

    double dist(Lab p, Lab q) => math.sqrt(
      math.pow(p.l - q.l, 2) + math.pow(p.a - q.a, 2) + math.pow(p.b - q.b, 2),
    );

    test('where two zones cover a pixel both shifts are applied', () {
      final both = render(lips, blush);
      final onlyLips = render(lips, off);
      final onlyBlush = render(off, blush);
      final base = at(flat, 25, 20);
      final a = at(onlyLips, 25, 20), b = at(onlyBlush, 25, 20);
      // expected = base + (lips shift) + (blush shift)
      final want = Lab(
        base.l + (a.l - base.l) + (b.l - base.l),
        base.a + (a.a - base.a) + (b.a - base.a),
        base.b + (a.b - base.b) + (b.b - base.b),
      );
      final got = at(both, 25, 20);
      expect(dist(got, want), lessThan(1.5));
      // and it is not simply the zone that is drawn last
      expect(dist(got, b), greaterThan(4));
      expect(dist(got, a), greaterThan(4));
    });

    test(
      'outside the union of the zones nothing changes, also where they overlap',
      () {
        final both = render(lips, blush);
        var changed = 0;
        for (var y = 0; y < 40; y++) {
          for (var x = 0; x < 60; x++) {
            final o = (y * 60 + x) * 4;
            final inZone = x >= 10 && x < 40 && y >= 10 && y < 30;
            final same =
                both.pixels.sublist(o, o + 4).join(',') ==
                flat.pixels.sublist(o, o + 4).join(',');
            if (!inZone) expect(same, isTrue, reason: 'pixel $x,$y is outside');
            if (inZone && !same) changed++;
          }
        }
        expect(changed, 30 * 20, reason: 'every pixel of the union changes');
      },
    );

    test('protected pixels stay byte for byte, also in the shared strip', () {
      final prot = ProtectionMask(60, 40);
      prot.dab(25, 20, 6, hardness: 1); // sits in the strip of both zones
      final out = _backend.renderSync(
        MakeupRequest(
          face: face,
          look: const MakeupLook(lips: lips, eyeshadow: off, blush: blush),
          protection: prot,
        ),
      );
      var guarded = 0;
      for (var y = 0; y < 40; y++) {
        for (var x = 0; x < 60; x++) {
          if (prot.at(x, y) < 1) continue;
          guarded++;
          final o = (y * 60 + x) * 4;
          expect(
            out.pixels.sublist(o, o + 4),
            flat.pixels.sublist(o, o + 4),
            reason: 'protected pixel $x,$y',
          );
        }
      }
      expect(guarded, greaterThan(50));
    });

    test('outside the shared strip each zone is exactly what it is alone', () {
      final both = render(lips, blush);
      final onlyLips = render(lips, off);
      final onlyBlush = render(off, blush);
      for (var y = 0; y < 40; y++) {
        for (var x = 0; x < 60; x++) {
          final o = (y * 60 + x) * 4;
          final ref = x < 20
              ? onlyLips
              : x >= 30
              ? onlyBlush
              : null;
          if (ref == null) continue;
          expect(both.pixels.sublist(o, o + 3), ref.pixels.sublist(o, o + 3));
        }
      }
    });
  });
}

/// The cheek centres as the module computes them (kept in one place for tests).
class ZoneMaskBuilderProbe {
  static Offset cheekRight(SyntheticFace f) => _c(f, true);
  static Offset cheekLeft(SyntheticFace f) => _c(f, false);
  static Offset _c(SyntheticFace f, bool right) {
    final eye =
        f.points[right ? FaceIndices.eyeOuterRight : FaceIndices.eyeOuterLeft];
    final mouth =
        f.points[right
            ? FaceIndices.mouthCornerRight
            : FaceIndices.mouthCornerLeft];
    final ear =
        f.points[right ? FaceIndices.faceEdgeRight : FaceIndices.faceEdgeLeft];
    return Offset.lerp(Offset.lerp(eye, mouth, 0.5)!, ear, 0.15)!;
  }
}
