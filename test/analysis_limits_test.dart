import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/app.dart';
import 'package:cosmetix/core/beauty/beauty_codes.dart';
import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/models/beauty_profile.dart';
import 'package:cosmetix/repositories/user_repository.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/routes/route_args.dart';
import 'package:cosmetix/services/color_test_service.dart';
import 'widget_test.dart' show pumpUntil;

/// Before the photo step and next to the result the user is told what the
/// analysis is and is not: a colour hint, not a measurement, not a diagnosis,
/// and nothing about acne, scars or redness.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  currentLang = AppLang.ru;

  Future<DatabaseHelper> boot(WidgetTester t) async {
    t.view.physicalSize = const Size(1080, 2600);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final helper = DatabaseHelper(path: inMemoryDatabasePath);
    addTearDown(() => t.runAsync(helper.close));
    final users = UserRepository(helper);
    await t.runAsync(() async {
      final u = await users.register(
        firstName: 'Новая',
        email: 'new@test.kz',
        password: 'Passw0rd1',
      );
      await users.setCurrentUser(u.id);
      // an adult: since the age gate (PR #28) a user of unknown age gets an
      // explanation instead of the photo step this test looks at
      await (await helper.database).update(
        'users',
        {'birth_year': 1990},
        where: 'id = ?',
        whereArgs: [u.id],
      );
    });
    await t.pumpWidget(CosmetixApp(helper: helper));
    await pumpUntil(t, find.text('Кабинет'));
    return helper;
  }

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  NavigatorState nav(WidgetTester t) =>
      t.state<NavigatorState>(find.byType(Navigator).first);

  testWidgets('the photo step says what the analysis is and is not', (t) async {
    await boot(t);
    nav(t).pushNamed(
      AppRoutes.beautyPhoto,
      arguments: const BeautyPhotoArgs(
        color: ColorTestResult(
          colorType: 'Лето',
          undertone: 'Холодный',
          skinTone: 'Светлый',
        ),
        skinType: SkinType.dry,
        concerns: {SkinConcern.dryness},
      ),
    );
    await settle(t);
    for (final s in [
      'Что стоит знать об анализе по фото',
      'Это подсказка по цвету, а не измерение и не диагноз.',
      'Результат зависит от света и камеры; макияж, очки и фильтры его искажают.',
      'Приложение не определяет акне, рубцы или покраснения.',
    ]) {
      expect(find.text(s, skipOffstage: false), findsOneWidget, reason: s);
    }
  });

  testWidgets(
    'the result screen says it is a hint, not a measurement or a diagnosis',
    (t) async {
      await boot(t);
      nav(t).pushNamed(
        AppRoutes.colorResult,
        arguments: BeautyResultArgs(
          profile: BeautyProfile.fromLabels(
            skinType: 'Сухая',
            skinTone: 'Светлый',
            undertone: 'Холодный',
            colorType: 'Лето',
            concerns: const ['Сухость и шелушение'],
          ),
        ),
      );
      await settle(t);
      expect(
        find.textContaining('а не измерение и не диагноз', skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.textContaining('ориентировочный', skipOffstage: false),
        findsOneWidget,
      );
    },
  );
}
