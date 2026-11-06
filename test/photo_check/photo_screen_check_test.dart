import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/core/beauty/beauty_codes.dart';
import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/theme/app_theme.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/models/ai_models.dart';
import 'package:cosmetix/providers/ai_provider.dart';
import 'package:cosmetix/providers/auth_provider.dart';
import 'package:cosmetix/providers/cart_provider.dart';
import 'package:cosmetix/providers/nav_provider.dart';
import 'package:cosmetix/repositories/cart_repository.dart';
import 'package:cosmetix/repositories/settings_repository.dart';
import 'package:cosmetix/repositories/user_repository.dart';
import 'package:cosmetix/routes/route_args.dart';
import 'package:cosmetix/screens/beauty/beauty_photo_screen.dart';
import 'package:cosmetix/screens/beauty/photo_issue_text.dart';
import 'package:cosmetix/services/ai/ai_client.dart';
import 'package:cosmetix/services/ai/ai_config.dart';
import 'package:cosmetix/services/ai/vision_analyzer.dart';
import 'package:cosmetix/services/color_test_service.dart';
import 'package:cosmetix/services/photo_check/photo_check.dart';

import 'synthetic_face.dart';

/// What the user sees when the local check refuses a photo, and the proof that a
/// refused photo goes nowhere: no HTTP client is even created, the analyzer is
/// never called, the file is deleted and the saved profile does not change.

/// Counts every attempt to create an HTTP client (any network access).
class _NetSpy extends HttpOverrides {
  int clients = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    clients++;
    return super.createHttpClient(context);
  }
}

class _CountingAnalyzer extends VisionAnalyzer {
  _CountingAnalyzer() : super(AiClient(() => const AiConfig(baseUrl: '')));

  int calls = 0;

  @override
  Future<VisionAnalysis> analyzeFile(File photo) async {
    calls++;
    throw const AiBadResponse('test analyzer: stop here');
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  currentLang = AppLang.ru;

  const args = BeautyPhotoArgs(
    color: ColorTestResult(
      colorType: 'Лето',
      undertone: 'Холодный',
      skinTone: 'Светлый',
    ),
    skinType: SkinType.dry,
    concerns: {SkinConcern.dryness},
  );

  Future<File> writePng(WidgetTester t, Canvas8 c) async {
    final bytes = await t.runAsync(() async {
      final done = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        c.rgba,
        c.w,
        c.h,
        ui.PixelFormat.rgba8888,
        done.complete,
      );
      final img = await done.future;
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    final f = File(
      '${Directory.systemTemp.path}/cosmetix_check_${DateTime.now().microsecondsSinceEpoch}.png',
    );
    f.writeAsBytesSync(bytes!);
    addTearDown(() {
      if (f.existsSync()) f.deleteSync();
    });
    return f;
  }

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 8; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<
    ({
      _CountingAnalyzer analyzer,
      AuthProvider auth,
      AiProvider ai,
      _NetSpy spy,
    })
  >
  open(
    WidgetTester t,
    File file,
    PhotoFaceFinder finder, {
    _NetSpy? spy,
  }) async {
    t.view.physicalSize = const Size(1080, 4200);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final helper = DatabaseHelper(path: inMemoryDatabasePath);
    addTearDown(() => t.runAsync(helper.close));
    final users = UserRepository(helper);
    await t.runAsync(() async {
      final u = await users.register(
        firstName: 'Тест',
        email: 'check${DateTime.now().microsecondsSinceEpoch}@test.kz',
        password: 'Passw0rd1',
      );
      await users.setCurrentUser(u.id);
    });
    final auth = AuthProvider(users);
    await t.runAsync(auth.restoreSession);
    final ai =
        AiProvider(
            SettingsRepository(helper),
            initial: const AiConfig(baseUrl: 'http://127.0.0.1:1'),
          )
          ..status = AiStatus.online
          ..photoAnalysis = true
          ..ageSource = (() => 30);
    final analyzer = _CountingAnalyzer();
    await t.pumpWidget(
      const SizedBox(),
    ); // a fresh screen, not the state of the previous case
    await t.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AiProvider>.value(value: ai),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => NavProvider()),
          ChangeNotifierProvider(
            create: (_) => CartProvider(CartRepository(helper)),
          ),
          Provider<VisionAnalyzer>.value(value: analyzer),
          Provider<PhotoCheck>.value(value: PhotoCheck(finder)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: BeautyPhotoScreen(
            args: args,
            picker: (ImageSource s) async => file.path,
          ),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 100));
    return (analyzer: analyzer, auth: auth, ai: ai, spy: spy ?? _NetSpy());
  }

  Future<void> pickAndUse(WidgetTester t) async {
    await t.tap(find.text('Выбрать из галереи', skipOffstage: false));
    await settle(t);
    await t.tap(find.text('Использовать фото'));
    await settle(t);
  }

  const w = 900, h = 1000;
  final good = meshAt(Offset(w / 2, h / 2), 420);

  testWidgets(
    'no face: the reason, the way to another photo, nothing sent, the file deleted',
    (t) async {
      final spy = _NetSpy();
      await HttpOverrides.runWithHttpOverrides(() async {
        final file = await writePng(t, Canvas8(w, h)..face(good, lightSkin));
        final o = await open(t, file, FakeFinder([]), spy: spy);
        final before = o.auth.user!.beautyProfile.signature;
        await pickAndUse(t);
        expect(find.text('Это фото не подходит'), findsOneWidget);
        expect(find.textContaining('не нашли лицо'), findsOneWidget);
        expect(find.text('Выбрать другое фото'), findsOneWidget);
        expect(find.textContaining('Фото не отправлено'), findsOneWidget);
        expect(
          o.analyzer.calls,
          0,
          reason: 'a refused photo never reaches the analyzer',
        );
        expect(file.existsSync(), isFalse, reason: 'and it is deleted');
        expect(
          o.auth.user!.beautyProfile.signature,
          before,
          reason: 'the profile is unchanged',
        );
        expect(
          o.ai.sharePhotos,
          isFalse,
          reason: 'no consent was asked for a photo that was refused',
        );
      }, spy);
      expect(spy.clients, 0, reason: 'not a single network client was created');
    },
  );

  testWidgets(
    'several faces, a blurred photo and a turned head each show their own reason',
    (t) async {
      final spy = _NetSpy();
      await HttpOverrides.runWithHttpOverrides(() async {
        final second = meshAt(const Offset(200, 300), 300);
        final cases = <(String, Canvas8, List<List<Offset>>, String)>[
          (
            'several',
            Canvas8(w, h)
              ..face(good, lightSkin)
              ..face(second, mediumSkin),
            [good, second],
            'несколько лиц',
          ),
          (
            'blur',
            Canvas8(w, h)
              ..face(good, lightSkin)
              ..blur(7),
            [good],
            'нечёткое',
          ),
          (
            'turned',
            Canvas8(w, h)
              ..face(meshAt(Offset(w / 2, h / 2), 420, nose: 0.3), lightSkin),
            [meshAt(Offset(w / 2, h / 2), 420, nose: 0.3)],
            'повёрнуто',
          ),
          (
            'dark',
            Canvas8(w, h)
              ..face(good, lightSkin)
              ..gain(0.3),
            [good],
            'Слишком темно',
          ),
          (
            'glasses',
            Canvas8(w, h)
              ..face(good, lightSkin)
              ..lenses(good, 25),
            [good],
            'тёмными очками',
          ),
        ];
        for (final (name, canvas, faces, text) in cases) {
          final file = await writePng(t, canvas);
          final o = await open(t, file, FakeFinder(faces));
          await pickAndUse(t);
          expect(
            find.text('Это фото не подходит'),
            findsOneWidget,
            reason: name,
          );
          expect(find.textContaining(text), findsOneWidget, reason: name);
          expect(o.analyzer.calls, 0, reason: name);
          expect(file.existsSync(), isFalse, reason: name);
        }
      }, spy);
      expect(spy.clients, 0);
    },
  );

  testWidgets(
    'a damaged file: "cannot open", the detector is not asked, nothing sent',
    (t) async {
      final spy = _NetSpy();
      await HttpOverrides.runWithHttpOverrides(() async {
        final file = File('${Directory.systemTemp.path}/cosmetix_check_bad.png')
          ..writeAsBytesSync([1, 2, 3, 4, 5, 6, 7, 8]);
        addTearDown(() {
          if (file.existsSync()) file.deleteSync();
        });
        final finder = FakeFinder([good]);
        final o = await open(t, file, finder);
        await pickAndUse(t);
        expect(find.textContaining('Не удалось открыть фото'), findsOneWidget);
        expect(finder.calls, 0);
        expect(o.analyzer.calls, 0);
      }, spy);
      expect(spy.clients, 0);
    },
  );

  testWidgets('a failing detector is a refusal, not a pass', (t) async {
    final spy = _NetSpy();
    await HttpOverrides.runWithHttpOverrides(() async {
      final file = await writePng(t, Canvas8(w, h)..face(good, lightSkin));
      final o = await open(t, file, FakeFinder([], throws: true));
      await pickAndUse(t);
      expect(find.textContaining('Не удалось проверить фото'), findsOneWidget);
      expect(o.analyzer.calls, 0);
    }, spy);
    expect(spy.clients, 0);
  });

  testWidgets('a warning lets the user choose; nothing is sent until they do', (
    t,
  ) async {
    final far = meshAt(const Offset(150, 150), 90);
    final file = await writePng(
      t,
      Canvas8(w, h)
        ..face(good, lightSkin)
        ..face(far, mediumSkin),
    );
    final o = await open(t, file, FakeFinder([good, far]));
    await pickAndUse(t);
    expect(find.textContaining('можно использовать'), findsOneWidget);
    expect(find.textContaining('меньшее лицо'), findsOneWidget);
    expect(o.analyzer.calls, 0, reason: 'not yet: the user has not chosen');
    expect(file.existsSync(), isTrue);
    await t.tap(find.text('Использовать это фото'));
    await settle(t);
    // it goes on to the next steps (consent, then the analyzer); the test analyzer stops there
    expect(
      o.ai.sharePhotos ||
          o.analyzer.calls > 0 ||
          find.byType(AlertDialog).evaluate().isNotEmpty,
      isTrue,
    );
  });

  testWidgets('a good photo goes on to the analyzer (when consent is given)', (
    t,
  ) async {
    final file = await writePng(t, Canvas8(w, h)..face(good, mediumSkin));
    final o = await open(t, file, FakeFinder([good]));
    o.ai.sharePhotos = true; // consent already given
    await pickAndUse(t);
    expect(o.analyzer.calls, 1);
    expect(find.text('Это фото не подходит'), findsNothing);
  });

  testWidgets('another photo can be chosen after a refusal', (t) async {
    final file = await writePng(t, Canvas8(w, h)..face(good, lightSkin));
    await open(t, file, FakeFinder([]));
    await pickAndUse(t);
    await t.tap(find.text('Выбрать другое фото'));
    await settle(t);
    expect(
      find.text('Выбрать из галереи', skipOffstage: false),
      findsOneWidget,
    );
  });

  test(
    'every reason has a text in Russian and in English, and none shows a number',
    () {
      final cyr = RegExp('[А-Яа-яЁё]');
      for (final i in PhotoIssue.values) {
        currentLang = AppLang.ru;
        final ru = photoIssueText(i);
        expect(ru, isNotEmpty, reason: '$i');
        expect(
          ru,
          isNot(contains(RegExp(r'\d'))),
          reason: '$i: no number is shown to the user',
        );
        currentLang = AppLang.en;
        final en = photoIssueText(i);
        currentLang = AppLang.ru;
        expect(cyr.hasMatch(en), isFalse, reason: '$i is not translated: $en');
      }
    },
  );
}
