import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';

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
import 'package:cosmetix/services/ai/ai_client.dart';
import 'package:cosmetix/services/ai/ai_config.dart';
import 'package:cosmetix/services/ai/vision_analyzer.dart';
import 'package:cosmetix/services/color_test_service.dart';
import 'package:cosmetix/services/photo_check/photo_check.dart';

/// The REAL photo screen on a simulator with the REAL check (real decoder and
/// MediaPipe) and a counting analyzer in place of the network. For every photo it
/// shows the screen for [_hold] seconds (so that a screenshot can be taken from
/// outside: `PC_SCREEN <file> <state>` is printed first) and proves that a refused
/// photo reaches no analyzer, is deleted, and leaves the profile alone.
///
///   flutter test integration_test/photo_screen_sim_test.dart -d DEVICE \
///     --dart-define=SHOT_DIR=/path/to/photos --dart-define=SHOT_FILES=a.jpg,b.jpg \
///     --dart-define=SHOT_HOLD=12
const _dir = String.fromEnvironment('SHOT_DIR');
const _files = String.fromEnvironment('SHOT_FILES');
const _hold = int.fromEnvironment('SHOT_HOLD', defaultValue: 10);

class _CountingAnalyzer extends VisionAnalyzer {
  _CountingAnalyzer() : super(AiClient(() => const AiConfig(baseUrl: '')));
  int calls = 0;

  @override
  Future<VisionAnalysis> analyzeFile(File photo) async {
    calls++;
    throw const AiBadResponse('simulator test analyzer: stop here');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
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

  testWidgets('real screen, real check: what the user sees for each photo', (
    t,
  ) async {
    if (_dir.isEmpty || _files.isEmpty) {
      markTestSkipped('SHOT_DIR / SHOT_FILES are not set');
      return;
    }
    final helper = DatabaseHelper(path: inMemoryDatabasePath);
    final users = UserRepository(helper);
    final u = await users.register(
      firstName: 'Тест',
      email: 'sim${DateTime.now().microsecondsSinceEpoch}@test.kz',
      password: 'Passw0rd1',
    );
    await users.setCurrentUser(u.id);
    final auth = AuthProvider(users);
    await auth.restoreSession();
    final ai = AiProvider(
      SettingsRepository(helper),
      initial: const AiConfig(baseUrl: 'http://127.0.0.1:1'),
    )
      ..status = AiStatus.online
      ..photoAnalysis = true
      ..ageSource = (() => 30);
    final analyzer = _CountingAnalyzer();
    final check = PhotoCheck(MediaPipePhotoFaceFinder());
    addTearDown(check.dispose);
    final before = auth.user!.beautyProfile.signature;

    for (final name in _files.split(',')) {
      final copy = File('${Directory.systemTemp.path}/sim_$name')
        ..writeAsBytesSync(File('$_dir/$name').readAsBytesSync());
      await t.pumpWidget(const SizedBox());
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
            Provider<PhotoCheck>.value(value: check),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: BeautyPhotoScreen(
              args: args,
              picker: (ImageSource s) async => copy.path,
            ),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.text('Выбрать из галереи', skipOffstage: false));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 200));
      }
      await t.tap(find.text('Использовать фото'));
      // the real check runs off the UI thread: wait for the result screen
      for (var i = 0; i < 60; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        await t.pump(const Duration(milliseconds: 100));
        if (find.text('Это фото не подходит').evaluate().isNotEmpty ||
            find.textContaining('можно использовать').evaluate().isNotEmpty ||
            find.byType(AlertDialog).evaluate().isNotEmpty) {
          break;
        }
      }
      final state = find.text('Это фото не подходит').evaluate().isNotEmpty
          ? 'REFUSED'
          : find.textContaining('можно использовать').evaluate().isNotEmpty
          ? 'WARNED'
          : find.byType(AlertDialog).evaluate().isNotEmpty
          ? 'CONSENT_DIALOG'
          : 'OTHER';
      debugPrint(
        'PC_SCREEN $name $state analyzerCalls=${analyzer.calls} '
        'fileExists=${copy.existsSync()} '
        'profileSame=${auth.user!.beautyProfile.signature == before}',
      );
      await t.runAsync(
        () => Future<void>.delayed(const Duration(seconds: _hold)),
      );
      await t.pump(const Duration(milliseconds: 200));
      if (state == 'REFUSED') {
        expect(analyzer.calls, 0, reason: name);
        expect(copy.existsSync(), isFalse, reason: name);
        expect(find.text('Использовать это фото'), findsNothing);
      }
      expect(auth.user!.beautyProfile.signature, before, reason: name);
      if (copy.existsSync()) copy.deleteSync();
    }
    expect(analyzer.calls, 0, reason: 'nothing here is allowed to be sent');
  });
}
