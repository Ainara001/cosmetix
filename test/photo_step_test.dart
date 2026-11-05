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

/// The photo step shows the camera buttons only when the AI server said it
/// accepts photos. No network here: the provider state is set directly.
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

  AiProvider online({required bool? photos}) {
    final ai = AiProvider(
      SettingsRepository(DatabaseHelper(path: inMemoryDatabasePath)),
      initial: const AiConfig(baseUrl: 'http://127.0.0.1:1'),
    );
    ai.status = AiStatus.online; // so initState does not call the network
    ai.photoAnalysis = photos;
    ai.ageSource = () =>
        30; // an adult: the age gate is not what is tested here
    return ai;
  }

  Future<void> open(WidgetTester t, AiProvider ai) async {
    t.view.physicalSize = const Size(
      1080,
      4200,
    ); // tall: a lazy list builds everything
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final helper = DatabaseHelper(path: inMemoryDatabasePath);
    addTearDown(() => t.runAsync(helper.close));
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

  testWidgets('photos off: an explanation instead of the camera buttons', (
    t,
  ) async {
    await open(t, online(photos: false));
    expect(
      find.textContaining('Анализ по фото сейчас отключён'),
      findsOneWidget,
    );
    expect(find.text('Сделать фото', skipOffstage: false), findsNothing);
    expect(find.text('Выбрать из галереи', skipOffstage: false), findsNothing);
    expect(find.text('Пропустить', skipOffstage: false), findsOneWidget);
  });

  testWidgets('an old proxy that does not say: also off', (t) async {
    await open(t, online(photos: null));
    expect(find.text('Сделать фото', skipOffstage: false), findsNothing);
  });

  testWidgets('photos on: the camera and gallery buttons are there', (t) async {
    await open(t, online(photos: true));
    expect(find.text('Сделать фото', skipOffstage: false), findsOneWidget);
    expect(
      find.text('Выбрать из галереи', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.textContaining('Анализ по фото сейчас отключён'), findsNothing);
  });
}
