import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cosmetix/services/photo_check/photo_check.dart';

import 'synthetic_face.dart';

/// The local photo check on synthetic faces (no real person, no network, no
/// plugin: the finder is a fake). The same rules run on real photos in
/// integration_test/photo_check_eval_test.dart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const w = 900, h = 1000;
  final center = Offset(w / 2, h / 2);

  Canvas8 photo(
    List<Offset> mesh,
    List<int> skin, {
    void Function(Canvas8)? edit,
  }) {
    final c = Canvas8(w, h)..face(mesh, skin);
    edit?.call(c);
    return c;
  }

  Future<PhotoCheckResult> check(Canvas8 c, List<List<Offset>> faces) =>
      PhotoCheck(FakeFinder(faces)).checkPixels(c.pixels);

  final good = meshAt(center, 420);

  group('a good photo', () {
    for (final (name, skin) in [
      ('light', lightSkin),
      ('medium', mediumSkin),
      ('dark', darkSkin),
    ]) {
      test('$name skin in good light is accepted without a warning', () async {
        final r = await check(photo(good, skin), [good]);
        expect(
          r.verdict.level,
          PhotoLevel.ok,
          reason: '${r.verdict} ${r.metrics?.toJson()}',
        );
        expect(r.metrics!.faceCount, 1);
      });
    }
  });

  group('refused before anything could be sent', () {
    test('no face', () async {
      final r = await check(photo(good, lightSkin), []);
      expect(r.verdict.level, PhotoLevel.reject);
      expect(r.verdict.issues, [PhotoIssue.noFace]);
      expect(r.metrics, isNull);
    });

    test('a failing detector is a refusal, not a pass', () async {
      final r = await PhotoCheck(
        FakeFinder([], throws: true),
      ).checkPixels(photo(good, lightSkin).pixels);
      expect(r.verdict.level, PhotoLevel.reject);
      expect(r.verdict.issues, [PhotoIssue.checkFailed]);
    });

    test('an empty, a damaged and a truncated file are unreadable', () async {
      final finder = FakeFinder([good]);
      final c = PhotoCheck(finder);
      for (final bytes in [
        Uint8List(0),
        Uint8List.fromList([1, 2, 3, 4, 5]),
        Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10, 0x4A, 0x46]),
      ]) {
        final r = await c.run(bytes);
        expect(r.verdict.level, PhotoLevel.reject);
        expect(r.verdict.issues, [PhotoIssue.unreadable]);
      }
      expect(
        finder.calls,
        0,
        reason:
            'the detector is not even asked about a file that cannot be read',
      );
    });

    test('two faces of a similar size', () async {
      final second = meshAt(const Offset(200, 300), 300);
      final c = photo(good, lightSkin, edit: (c) => c.face(second, mediumSkin));
      final r = await check(c, [good, second]);
      expect(r.verdict.level, PhotoLevel.reject);
      expect(r.verdict.issues, contains(PhotoIssue.severalFaces));
    });

    test(
      'the main face is the larger one whatever order the detector lists them',
      () async {
        final second = meshAt(const Offset(200, 300), 300);
        final c = photo(
          good,
          lightSkin,
          edit: (c) => c.face(second, mediumSkin),
        );
        final r = await check(c, [second, good]);
        expect(r.metrics!.facePx, closeTo(420, 1));
        expect(r.metrics!.secondFaceRatio, closeTo(300 / 420, 0.01));
      },
    );

    test('a small face in the background is only a warning', () async {
      final far = meshAt(const Offset(150, 150), 90);
      final c = photo(good, lightSkin, edit: (c) => c.face(far, mediumSkin));
      final r = await check(c, [good, far]);
      expect(r.verdict.level, PhotoLevel.warn);
      expect(r.verdict.issues, contains(PhotoIssue.backgroundFace));
    });

    test('a small, far face', () async {
      final tiny = meshAt(center, 80);
      final r = await check(photo(tiny, lightSkin), [tiny]);
      expect(r.verdict.level, PhotoLevel.reject);
      expect(r.verdict.issues, contains(PhotoIssue.faceSmall));
    });

    test('a blurred photo', () async {
      final r = await check(photo(good, lightSkin, edit: (c) => c.blur(7)), [
        good,
      ]);
      expect(r.verdict.level, PhotoLevel.reject);
      expect(r.verdict.issues, contains(PhotoIssue.blurry));
    });

    test('a photo that is too dark', () async {
      final r = await check(photo(good, lightSkin, edit: (c) => c.gain(0.3)), [
        good,
      ]);
      expect(r.verdict.level, PhotoLevel.reject);
      expect(r.verdict.issues, contains(PhotoIssue.tooDark));
    });

    test('a face blown out by light', () async {
      final r = await check(photo(good, lightSkin, edit: (c) => c.gain(1.9)), [
        good,
      ]);
      expect(r.verdict.level, PhotoLevel.reject);
      expect(r.verdict.issues, contains(PhotoIssue.overexposed));
    });

    test('a black and white photo', () async {
      final r = await check(photo(good, const [150, 150, 150]), [good]);
      expect(r.verdict.level, PhotoLevel.reject);
      expect(r.verdict.issues, contains(PhotoIssue.grayscale));
    });

    test('a turned head', () async {
      final turned = meshAt(center, 420, nose: 0.3);
      final r = await check(photo(turned, lightSkin), [turned]);
      expect(r.verdict.level, PhotoLevel.reject);
      expect(r.verdict.issues, contains(PhotoIssue.turned));
      expect(r.metrics!.yawOffset, closeTo(0.3, 0.03));
    });

    test('dark lenses over the eyes', () async {
      final r = await check(
        photo(good, lightSkin, edit: (c) => c.lenses(good, 25)),
        [good],
      );
      expect(r.verdict.level, PhotoLevel.reject);
      expect(r.verdict.issues, contains(PhotoIssue.eyesCovered));
    });

    test('open eyes on dark skin are not "covered"', () async {
      final r = await check(photo(good, darkSkin), [good]);
      expect(r.verdict.issues, isNot(contains(PhotoIssue.eyesCovered)));
    });
  });

  group('dark skin is judged against itself, not against a light face', () {
    test('every tone gives the same verdict for the same photo', () async {
      final levels = <PhotoLevel>{};
      for (final skin in [lightSkin, mediumSkin, darkSkin]) {
        levels.add((await check(photo(good, skin), [good])).verdict.level);
      }
      expect(levels, {PhotoLevel.ok});
    });

    test('a really dark photo is refused in any tone', () async {
      for (final skin in [lightSkin, mediumSkin, darkSkin]) {
        final r = await check(photo(good, skin, edit: (c) => c.gain(0.3)), [
          good,
        ]);
        expect(r.verdict.issues, contains(PhotoIssue.tooDark), reason: '$skin');
      }
    });
  });

  group('the rules', () {
    PhotoMetrics m({
      int faces = 1,
      double facePx = 400,
      double sharp = 300,
      double p95 = 200,
      double chroma = 15,
      double clipped = 0,
      double crushed = 0,
      double lr = 0.05,
      double yaw = 0.03,
      double second = 0,
      double eyeDark = 0.4,
      double eyeContrast = 0.3,
      double skinVisible = 0.9,
    }) => PhotoMetrics(
      faceCount: faces,
      facePx: facePx,
      sharpness: sharp,
      faceP95Luma: p95,
      skinChroma: chroma,
      clippedPct: clipped,
      crushedPct: crushed,
      lrAsym: lr,
      yawOffset: yaw,
      rollDeg: 0,
      secondFaceRatio: second,
      eyeDarkRatio: eyeDark,
      eyeContrast: eyeContrast,
      skinVisible: skinVisible,
    );

    test(
      'good numbers are ok',
      () => expect(PhotoThresholds.judge(m()).level, PhotoLevel.ok),
    );

    test(
      'each threshold: just inside is fine, just past it warns, far past it rejects',
      () {
        final cases =
            <(String, PhotoMetrics, PhotoMetrics, PhotoMetrics, PhotoIssue)>[
              (
                'size',
                m(facePx: 161),
                m(facePx: 159),
                m(facePx: 99),
                PhotoIssue.faceSmall,
              ),
              (
                'sharpness',
                m(sharp: 61),
                m(sharp: 59),
                m(sharp: 24),
                PhotoIssue.blurry,
              ),
              (
                'bright part',
                m(p95: 111),
                m(p95: 109),
                m(p95: 79),
                PhotoIssue.tooDark,
              ),
              (
                'colour',
                m(chroma: 3.1),
                m(chroma: 2.9),
                m(chroma: 1.9),
                PhotoIssue.grayscale,
              ),
              (
                'clipped',
                m(clipped: 3.9),
                m(clipped: 4.1),
                m(clipped: 12.1),
                PhotoIssue.overexposed,
              ),
              (
                'turn',
                m(yaw: 0.149),
                m(yaw: 0.151),
                m(yaw: 0.251),
                PhotoIssue.turned,
              ),
            ];
        for (final (name, fine, warn, reject, issue) in cases) {
          expect(
            PhotoThresholds.judge(fine).level,
            PhotoLevel.ok,
            reason: '$name fine',
          );
          final w = PhotoThresholds.judge(warn);
          expect(w.level, PhotoLevel.warn, reason: '$name warn');
          expect(w.issues, contains(issue));
          final r = PhotoThresholds.judge(reject);
          expect(r.level, PhotoLevel.reject, reason: '$name reject');
          expect(r.issues.first, issue);
        }
      },
    );

    test('side light and little visible skin only ever warn', () {
      expect(PhotoThresholds.judge(m(lr: 50)).level, PhotoLevel.warn);
      expect(
        PhotoThresholds.judge(m(skinVisible: 0.01)).level,
        PhotoLevel.warn,
      );
    });

    test(
      'eyes: dark and flat rejects; dark but alive, or flat but bright, does not',
      () {
        expect(
          PhotoThresholds.judge(m(eyeDark: 0.3, eyeContrast: 0.03)).level,
          PhotoLevel.reject,
        );
        expect(
          PhotoThresholds.judge(m(eyeDark: 0.3, eyeContrast: 0.2)).level,
          PhotoLevel.ok,
        );
        expect(
          PhotoThresholds.judge(m(eyeDark: 1.0, eyeContrast: 0.03)).level,
          PhotoLevel.ok,
          reason: 'closed eyelids',
        );
      },
    );

    test('NaN measurements never reject by themselves', () {
      final v = PhotoThresholds.judge(
        m(
          lr: double.nan,
          eyeDark: double.nan,
          eyeContrast: double.nan,
          skinVisible: double.nan,
        ),
      );
      expect(v.level, PhotoLevel.ok);
    });

    test('the worst reason decides, the worst is listed first', () {
      final v = PhotoThresholds.judge(m(sharp: 40, yaw: 0.3));
      expect(v.level, PhotoLevel.reject);
      expect(v.issues.first, PhotoIssue.turned);
      expect(v.issues, contains(PhotoIssue.blurry));
      expect(v.accepted, isFalse);
    });
  });
}
