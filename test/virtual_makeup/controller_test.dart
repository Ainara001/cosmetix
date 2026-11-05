import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cosmetix/features/virtual_makeup/domain/face_geometry.dart';
import 'package:cosmetix/features/virtual_makeup/engine/rgba_image.dart';
import 'package:cosmetix/features/virtual_makeup/landmarks/face_landmark_provider.dart';
import 'package:cosmetix/features/virtual_makeup/ui/virtual_makeup_controller.dart';

import 'screen_test.dart' show FakeLandmarks, pngOf;
import 'synthetic_face.dart';

/// A face finder whose answers are handed out by the test, one call at a time.
class GatedLandmarks implements FaceLandmarkProvider {
  final List<Completer<List<FacePoints>>> gates = [];
  bool disposed = false;

  @override
  Future<List<FacePoints>> detect(RgbaImage image) {
    final c = Completer<List<FacePoints>>();
    gates.add(c);
    return c.future;
  }

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  final face = SyntheticFace.build();
  late Uint8List png;
  const notAPicture = [1, 2, 3, 4];

  setUpAll(() async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    await binding.runAsync(() async => png = await pngOf(face.image));
  });

  /// Real time must pass for the image codecs; the test clock does not.
  Future<T> real<T>(WidgetTester t, Future<T> Function() body) async =>
      (await t.runAsync(body)) as T;

  /// Waits (in real time, so call it inside [real]) until [done] is true.
  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 300 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(done(), isTrue, reason: 'did not finish in time');
  }

  VirtualMakeupController make(FaceLandmarkProvider lm, {bool owns = true}) =>
      VirtualMakeupController(
        landmarks: lm,
        ownsLandmarks: owns,
        debounce: Duration.zero,
      );

  group('who frees the face finder', () {
    testWidgets('a controller frees the one it owns', (t) async {
      final lm = FakeLandmarks([face.points]);
      make(lm).dispose();
      await t.pump();
      expect(lm.disposed, isTrue);
    });

    testWidgets('a controller leaves alone one that was handed in', (t) async {
      final lm = FakeLandmarks([face.points]);
      make(lm, owns: false).dispose();
      await t.pump();
      expect(lm.disposed, isFalse);
    });
  });

  group('a photo that cannot be used', () {
    testWidgets('with no earlier photo the screen says why', (t) async {
      final lm = FakeLandmarks([]);
      final c = make(lm);
      await real(t, () => c.loadPhoto(png));
      expect(c.status, MakeupStatus.noFace);
      expect(c.notice, isNull);
      expect(c.hasPhoto, isFalse);

      lm.faces = [face.points, face.points];
      await real(t, () => c.loadPhoto(png));
      expect(c.status, MakeupStatus.severalFaces);

      await real(t, () => c.loadPhoto(Uint8List.fromList(notAPicture)));
      expect(c.status, MakeupStatus.failed);
      expect(c.hasPhoto, isFalse);
      c.dispose();
    });

    for (final (name, faces, bytes, want)
        in <(String, List<FacePoints>, List<int>, MakeupNotice)>[
          ('has no face', <FacePoints>[], <int>[], MakeupNotice.noFace),
          (
            'has several faces',
            [face.points, face.points],
            <int>[],
            MakeupNotice.severalFaces,
          ),
          ('is not a picture', [face.points], notAPicture, MakeupNotice.failed),
        ]) {
      testWidgets('a second photo that $name keeps the first one', (t) async {
        final lm = FakeLandmarks([face.points]);
        final c = make(lm);
        await real(t, () => c.loadPhoto(png));
        expect(c.status, MakeupStatus.ready);
        final first = c.face;
        final shown = c.resultImage;
        expect(first, isNotNull);

        lm.faces = faces;
        await real(
          t,
          () => c.loadPhoto(bytes.isEmpty ? png : Uint8List.fromList(bytes)),
        );
        expect(
          c.status,
          MakeupStatus.ready,
          reason: 'still on the first photo',
        );
        expect(c.notice, want);
        expect(identical(c.face, first), isTrue);
        expect(identical(c.resultImage, shown), isTrue);
        expect(c.protection, isNotNull);

        // a good photo clears the notice again
        lm.faces = [face.points];
        await real(t, () => c.loadPhoto(png));
        expect(c.status, MakeupStatus.ready);
        expect(c.notice, isNull);
        expect(identical(c.face, first), isFalse);
        c.dispose();
      });
    }
  });

  group('two photos at once', () {
    testWidgets('the newer one wins even if the older answers last', (t) async {
      final lm = GatedLandmarks();
      final c = make(lm);
      await real(t, () async {
        final slow = c.loadPhoto(png); // call 0
        final fast = c.loadPhoto(png); // call 1
        await until(() => lm.gates.length == 2);
        lm.gates[1].complete([face.points]);
        await fast;
        expect(c.status, MakeupStatus.ready);
        final winner = c.face;
        expect(winner, isNotNull);

        // the older call now finds TWO faces: it must not touch the screen
        lm.gates[0].complete([face.points, face.points]);
        await slow;
        expect(c.status, MakeupStatus.ready);
        expect(c.notice, isNull);
        expect(identical(c.face, winner), isTrue);
      });
      c.dispose();
    });

    testWidgets('leaving while a photo loads does nothing afterwards', (
      t,
    ) async {
      final lm = GatedLandmarks();
      final c = make(lm);
      var notified = 0;
      c.addListener(() => notified++);
      await real(t, () async {
        final pending = c.loadPhoto(png);
        await until(() => lm.gates.length == 1);
        c.dispose();
        final before = notified;
        lm.gates[0].complete([face.points]);
        await pending;
        expect(notified, before);
      });
      expect(t.takeException(), isNull);
    });
  });

  group('the protection picture follows the brush', () {
    Future<Uint8List> pixelsOf(ui.Image i) async {
      final d = await i.toByteData(format: ui.ImageByteFormat.rawRgba);
      return d!.buffer.asUint8List();
    }

    testWidgets('a quick series of strokes ends with the last mask', (t) async {
      final c = make(FakeLandmarks([face.points]));
      await real(t, () async {
        await c.loadPhoto(png);
        final w = c.face!.image.width, h = c.face!.image.height;
        expect(c.protectionOverlay, isNull, reason: 'nothing protected yet');

        // many moves without waiting between them, as a finger does
        c.strokeStart(const ui.Offset(40, 40), 8, erase: false);
        for (var i = 1; i <= 60; i++) {
          c.strokeMove(ui.Offset(40.0 + i * 2, 40.0 + i), 8, erase: false);
        }
        c.strokeEnd();

        final want = VirtualMakeupController.overlayPixels(
          c.protection!.data,
          w,
          h,
          const [34, 160, 220],
        ).pixels;
        await until(() => c.protectionOverlay != null);
        // pictures arrive in a few rounds; the last one is the final mask
        var got = Uint8List(0);
        for (var i = 0; i < 100; i++) {
          got = await pixelsOf(c.protectionOverlay!);
          if (listEquals(got, want)) break;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(listEquals(got, want), isTrue);

        // taking everything away removes the picture
        c.clearProtection();
        await until(() => c.protectionOverlay == null);
      });
      c.dispose();
      await t.pump();
      expect(t.takeException(), isNull);
    });
  });
}
