import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/core/beauty/beauty_codes.dart';
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
import 'package:cosmetix/services/ai/ai_config.dart';
import 'package:cosmetix/services/color_test_service.dart';

/// Under 18 or age not given: the photo step is replaced by an explanation.
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

  Future<void> open(WidgetTester t, int? age) async {
    t.view.physicalSize = const Size(1080, 2200);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final helper = DatabaseHelper(path: inMemoryDatabasePath);
    addTearDown(() => t.runAsync(helper.close));
    final ai = AiProvider(
      SettingsRepository(helper),
      initial: const AiConfig(baseUrl: 'http://127.0.0.1:1'),
    );
    ai.status = AiStatus.online; // no network in this test
    ai.ageSource = () => age;
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
          home: const BeautyPhotoScreen(args: args),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 100));
  }

  testWidgets('a minor sees the age explanation and no camera buttons', (
    t,
  ) async {
    await open(t, 16);
    expect(find.text('Анализ по фото доступен с 18 лет'), findsOneWidget);
    expect(find.text('Сделать фото', skipOffstage: false), findsNothing);
    expect(find.text('Выбрать из галереи', skipOffstage: false), findsNothing);
    expect(find.textContaining('Укажите год рождения'), findsNothing);
  });

  testWidgets('an unknown age is asked to state the year of birth', (t) async {
    await open(t, null);
    expect(find.text('Анализ по фото доступен с 18 лет'), findsOneWidget);
    expect(find.textContaining('Укажите год рождения'), findsOneWidget);
    expect(find.text('Сделать фото', skipOffstage: false), findsNothing);
  });

  testWidgets('an adult gets the normal photo step', (t) async {
    await open(t, 30);
    expect(find.text('Анализ по фото доступен с 18 лет'), findsNothing);
    expect(find.text('Сделать фото', skipOffstage: false), findsOneWidget);
  });
}
