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

/// The capture buttons must stay on screen (pinned to the bottom) whatever the
/// device size or the accessibility text scale: the "what to know" card is
/// scrollable, the buttons are not pushed down by it.
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

  AiProvider online() {
    final ai = AiProvider(
      SettingsRepository(DatabaseHelper(path: inMemoryDatabasePath)),
      initial: const AiConfig(baseUrl: 'http://127.0.0.1:1'),
    );
    ai.status = AiStatus.online;
    ai.photoAnalysis = true;
    ai.ageSource = () => 30;
    return ai;
  }

  Future<void> pumpStep(
    WidgetTester t,
    AiProvider ai, {
    required Size logical,
    double textScale = 1.0,
  }) async {
    t.view.physicalSize = logical;
    t.view.devicePixelRatio = 1.0;
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
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const BeautyPhotoScreen(args: args),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 100));
  }

  final cases = <(String, Size, double)>[
    ('iPhone SE', const Size(375, 667), 1.0),
    ('iPhone 16 Pro Max', const Size(440, 956), 1.0),
    ('iPhone SE with 2x text', const Size(375, 667), 2.0),
  ];

  for (final c in cases) {
    testWidgets('capture buttons stay visible on ${c.$1}', (t) async {
      await pumpStep(t, online(), logical: c.$2, textScale: c.$3);
      expect(find.text('Сделать фото').hitTestable(), findsOneWidget);
      expect(find.text('Выбрать из галереи').hitTestable(), findsOneWidget);
      expect(find.text('Пропустить').hitTestable(), findsOneWidget);
    });
  }
}
