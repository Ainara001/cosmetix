import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/app.dart';
import 'package:cosmetix/core/beauty/beauty_codes.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/models/beauty_profile.dart';
import 'package:cosmetix/repositories/user_repository.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/routes/route_args.dart';
import 'package:cosmetix/services/color_test_service.dart';
import 'widget_test.dart' show pumpUntil;

/// Small phone + larger system font: the new Beauty/AI screens must not
/// overflow (a layout overflow throws in tests, so this fails on yellow stripes).
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  for (final scale in [1.0, 1.3]) {
    testWidgets('new screens fit a 360x640 phone at text scale $scale', (
      t,
    ) async {
      t.view.physicalSize = const Size(360 * 3, 640 * 3);
      t.view.devicePixelRatio = 3;
      t.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(t.view.reset);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      final helper = DatabaseHelper(path: inMemoryDatabasePath);
      addTearDown(() => t.runAsync(helper.close));
      await t.runAsync(() => UserRepository(helper).setCurrentUser(1));
      await t.pumpWidget(CosmetixApp(helper: helper));
      await pumpUntil(t, find.text('Кабинет'));
      await settle(t);

      final nav = t.state<NavigatorState>(find.byType(Navigator).first);
      const color = ColorTestResult(
        colorType: 'Лето',
        undertone: 'Холодный',
        skinTone: 'Светлый',
      );
      final screens = <(String, Object?)>[
        (AppRoutes.catalog, null),
        (AppRoutes.skinTest, const SkinTestArgs(color: color)),
        (
          AppRoutes.beautyPhoto,
          const BeautyPhotoArgs(
            color: color,
            skinType: SkinType.dry,
            concerns: {SkinConcern.dryness},
          ),
        ),
        (
          AppRoutes.colorResult,
          BeautyResultArgs(
            profile: BeautyProfile.fromLabels(
              skinType: 'Комбинированная',
              skinTone: 'Очень светлый',
              undertone: 'Нейтральный',
              colorType: 'Зима',
              concerns: const [
                'Сухость и шелушение',
                'Чувствительность и покраснения',
                'Морщины и возраст',
              ],
              source: 'questionnaire_photo',
              confidence: 0.82,
            ),
            photoUsed: true,
            observations: const ['Even skin tone', 'No strong makeup'],
          ),
        ),
        (AppRoutes.product, 3),
        (AppRoutes.settings, null),
        (AppRoutes.beautyProfile, null),
        (AppRoutes.editProfile, null),
      ];
      for (final (route, args) in screens) {
        nav.pushNamed(route, arguments: args);
        await settle(t);
        nav.pop();
        await settle(t);
      }
      // the home screen with the "Recommended for you" block
      await settle(t);
    });
  }
}
