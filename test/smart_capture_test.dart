import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/core/beauty/beauty_codes.dart';
import 'package:cosmetix/core/face/capture_guidance.dart';
import 'package:cosmetix/core/face/face_coordinate_transform.dart';
import 'package:cosmetix/core/face/face_geometry.dart';
import 'package:cosmetix/core/face/face_points.dart';
import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/theme/app_theme.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/providers/ai_provider.dart';
import 'package:cosmetix/providers/cart_provider.dart';
import 'package:cosmetix/providers/nav_provider.dart';
import 'package:cosmetix/repositories/cart_repository.dart';
import 'package:cosmetix/repositories/settings_repository.dart';
import 'package:cosmetix/routes/route_args.dart';
import 'package:cosmetix/screens/beauty/beauty_photo_screen.dart';
import 'package:cosmetix/screens/beauty/smart_capture_screen.dart';
import 'package:cosmetix/services/ai/ai_config.dart';
import 'package:cosmetix/services/color_test_service.dart';

import 'photo_check/synthetic_face.dart';

/// A camera with made-up frames: no device, no photo of a real person.
class FakeCamera implements CaptureCamera {
  FakeCamera({this.fails, this.photoPath = '/nonexistent/photo.jpg'});

  final CameraProblem? fails;
  final String photoPath;
  void Function(LiveFrame)? onFrame;
  bool disposed = false;
  int pictures = 0;

  @override
  Future<void> start(void Function(LiveFrame) f) async {
    if (fails != null) throw CameraUnavailable(fails!);
    onFrame = f;
  }

  @override
  Size get previewSize => const Size(720, 1280);

  @override
  bool get mirrored => false;

  @override
  Widget buildPreview() => const ColoredBox(color: Color(0xFF445566));

  @override
  Future<String> takePicture() async {
    pictures++;
    return photoPath;
  }

  @override
  Future<void> dispose() async => disposed = true;
}

const screen = Size(390, 844);

/// A frontal face that lands in the guide oval of a [screen]-sized preview,
/// expressed in FRAME coordinates (what the camera would deliver).
LiveFrame goodFrame({double fill = 0.85, double luma = 180}) {
  final oval = CaptureThresholds.ovalFor(screen);
  final w = oval.width * fill;
  final mesh = meshAt(Offset.zero, w);
  final c = FaceGeometry(FacePoints(mesh), imageSize: screen).center;
  final inPreview = [for (final p in mesh) p - c + oval.center];
  const t = FaceCoordinateTransform(
    imageSize: Size(720, 1280),
    previewSize: screen,
  );
  return LiveFrame(
    face: FaceGeometry(
      FacePoints([for (final p in inPreview) t.toImage(p)]),
      imageSize: const Size(720, 1280),
    ),
    frameSize: const Size(720, 1280),
    faceLuma: luma,
  );
}

const noFace = LiveFrame(face: null, frameSize: Size(720, 1280));

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  setUp(() => currentLang = AppLang.ru);

  void phone(WidgetTester t, {Size size = screen, double text = 1}) {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = text;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  }

  /// Opens the smart camera from a button and returns what it gave back.
  Future<SmartCaptureResult? Function()> openCapture(
    WidgetTester t,
    FakeCamera cam,
  ) async {
    SmartCaptureResult? result;
    var done = false;
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await SmartCaptureScreen.open(context, camera: cam);
              done = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    return () {
      expect(done, isTrue, reason: 'the screen did not close');
      return result;
    };
  }

  Future<void> feed(WidgetTester t, FakeCamera cam, LiveFrame f, int n) async {
    for (var i = 0; i < n; i++) {
      cam.onFrame!(f);
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  String hint(WidgetTester t) =>
      t.widget<Text>(find.byKey(const Key('capture-hint'))).data!;

  testWidgets(
    'the hint follows the face, and turns to "ready" when it is placed well',
    (t) async {
      phone(t);
      final cam = FakeCamera();
      await openCapture(t, cam);
      await feed(t, cam, noFace, 2);
      expect(hint(t), 'Поместите лицо в овал');
      await feed(t, cam, goodFrame(fill: 0.5), 4);
      expect(hint(t), 'Поднесите телефон ближе');
      await feed(t, cam, goodFrame(), 8);
      expect(hint(t), 'Можно сделать фото');
      await feed(t, cam, goodFrame(luma: 60), 4);
      expect(hint(t), 'Добавьте освещения');
    },
  );

  testWidgets('the shutter always works and returns the photo', (t) async {
    phone(t);
    final cam = FakeCamera(photoPath: '/tmp/p.jpg');
    final result = await openCapture(t, cam);
    await feed(t, cam, noFace, 1); // not ready: still allowed
    await t.tap(find.byKey(const Key('capture-shutter')));
    await t.pumpAndSettle();
    final r = result();
    expect(r, isA<CapturedPhoto>());
    expect((r as CapturedPhoto).path, '/tmp/p.jpg');
    expect(cam.pictures, 1);
    expect(cam.disposed, isTrue, reason: 'the camera is released');
  });

  testWidgets('closing gives nothing back and releases the camera', (t) async {
    phone(t);
    final cam = FakeCamera();
    final result = await openCapture(t, cam);
    await t.tap(find.byTooltip('Закрыть'));
    await t.pumpAndSettle();
    expect(result(), isNull);
    expect(cam.disposed, isTrue);
  });

  testWidgets(
    'no camera (the simulator): back at once, the caller uses the system picker',
    (t) async {
      phone(t);
      final result = await openCapture(
        t,
        FakeCamera(fails: CameraProblem.noCamera),
      );
      expect(result(), isA<CameraNotAvailable>());
    },
  );

  testWidgets('no permission: an explanation and the gallery instead', (
    t,
  ) async {
    phone(t);
    final result = await openCapture(
      t,
      FakeCamera(fails: CameraProblem.denied),
    );
    expect(find.textContaining('Нет доступа к камере'), findsOneWidget);
    await t.tap(find.text('Выбрать из галереи'));
    await t.pumpAndSettle();
    expect(result(), isA<UseGallery>());
  });

  testWidgets('the Face Mesh points can be shown and hidden', (t) async {
    phone(t);
    final cam = FakeCamera();
    await openCapture(t, cam);
    await feed(t, cam, goodFrame(), 2);
    expect(find.byTooltip('Показать точки лица'), findsOneWidget);
    await t.tap(find.byTooltip('Показать точки лица'));
    await t.pump();
    expect(find.byTooltip('Скрыть точки лица'), findsOneWidget);
  });

  for (final (name, size) in [
    ('iPhone SE', const Size(375, 667)),
    ('iPhone 16 Pro Max', const Size(440, 956)),
  ]) {
    testWidgets('$name with 2x text: no overflow, the shutter is on screen', (
      t,
    ) async {
      phone(t, size: size, text: 2);
      final cam = FakeCamera();
      await openCapture(t, cam);
      await feed(t, cam, goodFrame(fill: 0.5), 4);
      expect(t.takeException(), isNull);
      final shutter = t.getRect(find.byKey(const Key('capture-shutter')));
      expect(shutter.bottom, lessThanOrEqualTo(size.height));
      expect(shutter.width, greaterThanOrEqualTo(44), reason: 'touch target');
    });
  }

  test('every hint and message is translated (EN, KK)', () {
    final texts = [
      for (final h in CaptureHint.values) captureHintText(h),
      'Нет доступа к камере. Разрешите его в Настройках iPhone или выберите фото из галереи.',
      'Камера не запустилась. Выберите фото из галереи.',
      'Выбрать из галереи',
      'Закрыть',
      'Скрыть точки лица',
      'Показать точки лица',
      'Запускаем камеру…',
      'Сделать фото',
    ];
    for (final lang in [AppLang.en, AppLang.kk]) {
      currentLang = lang;
      final ru = [
        for (final s in texts)
          if (tr(s) == s) s,
      ];
      expect(ru, isEmpty, reason: 'not translated in $lang');
    }
    currentLang = AppLang.ru;
    expect(
      CaptureHint.values.map(captureHintText).toSet().length,
      CaptureHint.values.length,
      reason: 'each hint has its own text',
    );
  });

  testWidgets(
    'the photo step opens the smart camera; its photo goes to the preview',
    (t) async {
      t.view.physicalSize = const Size(1080, 3600);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final helper = DatabaseHelper(path: inMemoryDatabasePath);
      addTearDown(() => t.runAsync(helper.close));
      final ai =
          AiProvider(
              SettingsRepository(helper),
              initial: const AiConfig(baseUrl: 'http://127.0.0.1:1'),
            )
            ..status = AiStatus.online
            ..photoAnalysis = true
            ..ageSource = (() => 30);
      // a 1x1 PNG: the preview only needs a file
      final file =
          File(
            '${Directory.systemTemp.path}/cosmetix_capture_${DateTime.now().microsecondsSinceEpoch}.png',
          )..writeAsBytesSync(
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
            ),
          );
      addTearDown(() {
        if (file.existsSync()) file.deleteSync();
      });
      final cam = FakeCamera(photoPath: file.path);
      await t.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AiProvider>.value(value: ai),
            ChangeNotifierProvider(create: (_) => NavProvider()),
            ChangeNotifierProvider(
              create: (_) => CartProvider(CartRepository(helper)),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: BeautyPhotoScreen(
              args: const BeautyPhotoArgs(
                color: ColorTestResult(
                  colorType: 'Лето',
                  undertone: 'Холодный',
                  skinTone: 'Светлый',
                ),
                skinType: SkinType.dry,
                concerns: {SkinConcern.dryness},
              ),
              captureCamera: () => cam,
            ),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 100));
      await t.tap(find.text('Сделать фото', skipOffstage: false));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('capture-hint')), findsOneWidget);
      await t.tap(find.byKey(const Key('capture-shutter')));
      await t.pumpAndSettle();
      expect(find.text('Использовать фото'), findsOneWidget);
      expect(cam.disposed, isTrue);
    },
  );
}
