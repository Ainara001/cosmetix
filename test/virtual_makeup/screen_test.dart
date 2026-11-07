import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cosmetix/widgets/pill_segments.dart';
import 'package:cosmetix/core/theme/app_theme.dart';
import 'package:cosmetix/features/virtual_makeup/domain/face_geometry.dart';
import 'package:cosmetix/features/virtual_makeup/engine/rgba_image.dart';
import 'package:cosmetix/features/virtual_makeup/landmarks/face_landmark_provider.dart';
import 'package:cosmetix/features/virtual_makeup/ui/photo_io.dart';
import 'package:cosmetix/features/virtual_makeup/ui/virtual_makeup_screen.dart';
import 'package:cosmetix/features/virtual_makeup/domain/face_quality.dart';
import 'package:cosmetix/features/virtual_makeup/ui/virtual_makeup_controller.dart';

import 'synthetic_face.dart';

/// Finds whatever faces the test says. It does not look at the photo.
class FakeLandmarks implements FaceLandmarkProvider {
  FakeLandmarks(this.faces);
  List<FacePoints> faces;
  int calls = 0;
  bool disposed = false;

  @override
  Future<List<FacePoints>> detect(RgbaImage image) async {
    calls++;
    return faces;
  }

  @override
  Future<void> dispose() async => disposed = true;
}

class FakePhotos implements MakeupPhotoSource {
  FakePhotos(this.bytes);
  Uint8List? bytes;
  int picks = 0;
  bool? lastCamera;

  @override
  Future<Uint8List?> pick({required bool camera}) async {
    picks++;
    lastCamera = camera;
    return bytes;
  }
}

Future<Uint8List> pngOf(RgbaImage img) async {
  final ui.Image i = await PhotoDecoder.toUiImage(img);
  final data = await i.toByteData(format: ui.ImageByteFormat.png);
  i.dispose();
  return data!.buffer.asUint8List();
}

Widget host(Widget child) => MaterialApp(theme: AppTheme.light(), home: child);

/// The screen is a lazy list: bring a widget into view before using it.
Future<void> reveal(WidgetTester t, Finder f) async {
  await t.scrollUntilVisible(f, 150, scrollable: find.byType(Scrollable).first);
  await t.pump();
}

Future<void> settle(WidgetTester t, Finder until, {int max = 60}) async {
  for (var i = 0; i < max && until.evaluate().isEmpty; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await t.pump(const Duration(milliseconds: 50));
  }
  await t.pump();
}

void main() {
  test(
    'the mask overlay is premultiplied: clear where nothing is protected',
    () {
      final mask = Uint8List.fromList([0, 255, 128, 0]);
      final o = VirtualMakeupController.overlayPixels(mask, 2, 2, const [
        200,
        100,
        50,
      ]);
      expect(o.pixels.sublist(0, 4), [
        0,
        0,
        0,
        0,
      ], reason: 'transparent means every channel is 0');
      expect(o.pixels[7], 140); // 55 % of 255
      // colour = colour * alpha / 255: never brighter than its own alpha
      for (var i = 0; i < 4; i++) {
        final a = o.pixels[i * 4 + 3];
        expect(o.pixels[i * 4], lessThanOrEqualTo(a));
        expect(o.pixels[i * 4 + 1], lessThanOrEqualTo(a));
        expect(o.pixels[i * 4 + 2], lessThanOrEqualTo(a));
      }
    },
  );

  late SyntheticFace face;
  late Uint8List png;

  setUpAll(() async {
    face = SyntheticFace.build();
    png = (await _runAsyncPng(face.image));
  });

  Future<(FakeLandmarks, FakePhotos)> open(
    WidgetTester t, {
    List<FacePoints>? faces,
    Size size = const Size(420, 900),
  }) async {
    t.view.physicalSize = size * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final lm = FakeLandmarks(faces ?? [face.points]);
    final photos = FakePhotos(png);
    await t.pumpWidget(
      host(VirtualMakeupScreen(landmarks: lm, photos: photos)),
    );
    return (lm, photos);
  }

  Future<void> pickPhoto(WidgetTester t) async {
    await t.tap(find.byKey(const Key('vm-gallery')));
    await settle(t, find.byKey(const Key('vm-photo')));
  }

  testWidgets(
    'the first screen: privacy, two ways to get a photo, the disclaimer',
    (t) async {
      final (lm, _) = await open(t);
      expect(find.byKey(const Key('vm-disclaimer')), findsOneWidget);
      expect(find.textContaining('не отправляется на сервер'), findsOneWidget);
      expect(find.byKey(const Key('vm-gallery')), findsOneWidget);
      expect(find.byKey(const Key('vm-camera')), findsOneWidget);
      expect(find.byKey(const Key('vm-photo')), findsNothing);
      expect(
        lm.calls,
        0,
        reason: 'nothing is analysed before a photo is chosen',
      );
    },
  );

  testWidgets('a photo with one face: the preview and the controls appear', (
    t,
  ) async {
    final (lm, photos) = await open(t);
    await pickPhoto(t);
    expect(photos.picks, 1);
    expect(photos.lastCamera, isFalse);
    expect(lm.calls, 1);
    expect(find.byKey(const Key('vm-photo')), findsOneWidget);
    for (final z in ['lips', 'eyeshadow', 'blush']) {
      await reveal(t, find.byKey(Key('vm-zone-$z')));
      expect(find.byKey(Key('vm-zone-$z')), findsOneWidget);
    }
    expect(
      find.byKey(const Key('vm-disclaimer')),
      findsOneWidget,
      reason: 'always visible',
    );
    await t.drag(find.byType(Scrollable).first, const Offset(0, 2000));
    await t.pump();
    expect(find.byKey(const Key('vm-compare')), findsOneWidget);
  });

  testWidgets('the camera button asks the source for the camera', (t) async {
    final (_, photos) = await open(t);
    await t.tap(find.byKey(const Key('vm-camera')));
    await settle(t, find.byKey(const Key('vm-photo')));
    expect(photos.lastCamera, isTrue);
  });

  testWidgets('no face: a clear message, no result, nothing is guessed', (
    t,
  ) async {
    await open(t, faces: []);
    await t.tap(find.byKey(const Key('vm-gallery')));
    await settle(t, find.byKey(const Key('vm-no-face')));
    expect(find.byKey(const Key('vm-no-face')), findsOneWidget);
    expect(find.byKey(const Key('vm-photo')), findsNothing);
    expect(find.byKey(const Key('vm-disclaimer')), findsOneWidget);
  });

  testWidgets('several faces: the try-on is not run', (t) async {
    await open(t, faces: [face.points, face.points]);
    await t.tap(find.byKey(const Key('vm-gallery')));
    await settle(t, find.byKey(const Key('vm-several-faces')));
    expect(find.byKey(const Key('vm-several-faces')), findsOneWidget);
    expect(find.byKey(const Key('vm-photo')), findsNothing);
  });

  testWidgets('a turned head is shown as a warning, not hidden', (t) async {
    final pts = [...face.points.points];
    pts[FaceIndices.noseTip] = const Offset(150, 345);
    await open(t, faces: [FacePoints(pts)]);
    await pickPhoto(t);
    expect(
      find.byKey(Key('vm-issue-${QualityIssue.turnedHead.name}')),
      findsOneWidget,
    );
    expect(find.textContaining('Голова повёрнута'), findsOneWidget);
  });

  testWidgets('a broken photo is reported, not crashed on', (t) async {
    t.view.physicalSize = const Size(840, 1800);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      host(
        VirtualMakeupScreen(
          landmarks: FakeLandmarks([face.points]),
          photos: FakePhotos(Uint8List.fromList([1, 2, 3, 4])),
        ),
      ),
    );
    await t.tap(find.byKey(const Key('vm-gallery')));
    await settle(t, find.byKey(const Key('vm-failed')));
    expect(find.byKey(const Key('vm-failed')), findsOneWidget);
  });

  testWidgets('switches, swatches and the slider change the look', (t) async {
    await open(t);
    await pickPhoto(t);
    final slider = find.byKey(const Key('vm-slider-lips'));
    await reveal(t, slider);
    final rect = t.getRect(slider);
    await t.tapAt(Offset(rect.left + rect.width * 0.9, rect.center.dy));
    await t.pump();
    // the lips label moved up from 60 %
    final labels = [
      for (final w in t.widgetList<Text>(find.textContaining('Интенсивность:')))
        w.data,
    ];
    expect(labels.first, isNot('Интенсивность: 60%'));
    // switch a zone off
    await reveal(t, find.byKey(const Key('vm-switch-blush')));
    await t.tap(find.byKey(const Key('vm-switch-blush')));
    await t.pump();
    expect(
      t.widget<Switch>(find.byKey(const Key('vm-switch-blush'))).value,
      isFalse,
    );
    // pick another swatch
    await t.drag(find.byType(Scrollable).first, const Offset(0, 2000));
    await t.pump();
    await reveal(t, find.byKey(const Key('vm-swatch-lips-Розовый')));
    await t.tap(find.byKey(const Key('vm-swatch-lips-Розовый')));
    await t.pump();
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await t.pump();
  });

  testWidgets(
    'the compare control switches between result, original and the slider',
    (t) async {
      await open(t);
      await pickPhoto(t);
      PillSegments<CompareMode> sb() => t.widget<PillSegments<CompareMode>>(
        find.byKey(const Key('vm-compare')),
      );
      expect(sb().selected, CompareMode.result);
      await t.drag(find.byType(Scrollable).first, const Offset(0, 2000));
      await t.pump();
      await t.tap(find.text('Оригинал'));
      await t.pump();
      expect(sb().selected, CompareMode.original);
      await t.tap(find.text('Разделитель'));
      await t.pump();
      expect(sb().selected, CompareMode.split);
      expect(find.textContaining('Удерживайте фото'), findsOneWidget);
    },
  );

  testWidgets('protection: draw by hand, undo, redo, clear', (t) async {
    await open(t);
    await pickPhoto(t);
    await reveal(t, find.text('Защита кожи'));
    await t.tap(find.text('Защита кожи'));
    await t.pumpAndSettle();
    await reveal(t, find.byKey(const Key('vm-mask-panel')));
    expect(find.byKey(const Key('vm-mask-panel')), findsOneWidget);
    expect(find.textContaining('Защищено: 0.0% фото'), findsOneWidget);

    await t.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await t.pump();
    final photo = find.byKey(const Key('vm-photo'));
    final r = t.getRect(photo);
    final g = await t.startGesture(
      Offset(r.left + r.width * 0.35, r.top + r.height * 0.55),
    );
    await g.moveBy(const Offset(40, 0));
    await g.moveBy(const Offset(0, 30));
    await g.up();
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await t.pump();
    await reveal(t, find.byKey(const Key('vm-mask-panel')));
    expect(find.textContaining('Защищено: 0.0% фото'), findsNothing);

    await t.tap(find.byKey(const Key('vm-undo')));
    await t.pump();
    expect(find.textContaining('Защищено: 0.0% фото'), findsOneWidget);
    await t.tap(find.byKey(const Key('vm-redo')));
    await t.pump();
    expect(find.textContaining('Защищено: 0.0% фото'), findsNothing);
    await t.tap(find.byKey(const Key('vm-clear')));
    await t.pump();
    expect(find.textContaining('Защищено: 0.0% фото'), findsOneWidget);
  });

  testWidgets(
    'the suggestion is a hint: shown, then accepted or dismissed by the user',
    (t) async {
      await open(t);
      await pickPhoto(t);
      await reveal(t, find.text('Защита кожи'));
      await t.tap(find.text('Защита кожи'));
      await t.pumpAndSettle();
      // nothing is protected before the user accepts
      await reveal(t, find.byKey(const Key('vm-suggest')));
      await t.tap(find.byKey(const Key('vm-suggest')));
      await t.pump();
      await reveal(t, find.byKey(const Key('vm-suggest-found')));
      expect(find.byKey(const Key('vm-suggest-found')), findsOneWidget);
      await t.drag(find.byType(Scrollable).first, const Offset(0, 200));
      await t.pump();
      // a suggestion protects nothing until the user accepts it
      expect(find.textContaining('Защищено: 0.0% фото'), findsOneWidget);
      await reveal(t, find.byKey(const Key('vm-suggest-accept')));
      await t.tap(find.byKey(const Key('vm-suggest-accept')));
      await t.pump();
      expect(find.byKey(const Key('vm-suggest-found')), findsNothing);
      expect(find.textContaining('Защищено: 0.0% фото'), findsNothing);
    },
  );

  testWidgets('a small phone with large text: no overflow', (t) async {
    t.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(t.platformDispatcher.clearAllTestValues);
    await open(t, size: const Size(360, 640));
    expect(tester0(t), isNull);
    await pickPhoto(t);
    await t.drag(find.byType(ListView).first, const Offset(0, -600));
    await t.pump();
    expect(tester0(t), isNull);
  });

  testWidgets('leaving the screen keeps a face finder that was handed in', (
    t,
  ) async {
    final (lm, _) = await open(t);
    await t.pumpWidget(host(const SizedBox()));
    await t.pump();
    // the caller made it and may use it again; only a finder the screen made
    // itself is freed with the screen (covered in controller_test.dart)
    expect(lm.disposed, isFalse);
  });

  testWidgets('a refused second photo leaves the first on the screen', (
    t,
  ) async {
    final (lm, _) = await open(t);
    await pickPhoto(t);
    expect(find.byKey(const Key('vm-photo')), findsOneWidget);

    lm.faces = [];
    await reveal(t, find.byKey(const Key('vm-other-photo')));
    await t.tap(find.byKey(const Key('vm-other-photo')));
    // the notice is at the top of the list, which is now scrolled down
    for (
      var i = 0;
      i < 40 && find.byKey(const Key('vm-no-face')).evaluate().isEmpty;
      i++
    ) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await t.pump(const Duration(milliseconds: 50));
      await t.drag(find.byType(Scrollable).first, const Offset(0, 3000));
      await t.pump();
    }
    expect(find.byKey(const Key('vm-no-face')), findsOneWidget);
    expect(find.byKey(const Key('vm-photo')), findsOneWidget);
    expect(find.byKey(const Key('vm-tabs')), findsOneWidget);
  });
}

Object? tester0(WidgetTester t) => t.takeException();

Future<Uint8List> _runAsyncPng(RgbaImage img) async {
  late Uint8List out;
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  await binding.runAsync(() async => out = await pngOf(img));
  return out;
}
