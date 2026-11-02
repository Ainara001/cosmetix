import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/app.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/models/beauty_profile.dart';
import 'package:cosmetix/repositories/user_repository.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/routes/route_args.dart';
import 'package:cosmetix/services/color_test_service.dart';
import 'widget_test.dart' show pumpUntil;

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('colour type from realistic answers', () {
    // sums of the option scores (warm, depth) of the answers
    // eyes dark brown (0, 2) + hair black (0, 2) + skin deep (0, 2)
    // + sun "tan easily" (1, 1) + blush coral (1, 0)
    const warm = 2, depth = 7;

    test('warm colouring answers beat a single "blue veins" answer', () {
      final r = ColorTestService.compute(
        warm: warm,
        depth: depth,
        vein: -2, // blue veins
        answered: 5,
      );
      expect(r.colorType, 'Осень'); // not Зима
    });

    test('dark hair alone is not a cool signal', () {
      final r = ColorTestService.compute(
        warm: 0,
        depth: 4,
        vein: 0,
        answered: 2,
        veinAnswered: false,
      );
      expect(r.colorType, 'Осень'); // deep, nothing says "cool"
    });

    test('really cool answers still give Зима', () {
      final r = ColorTestService.compute(
        warm: -5, // blue eyes, silver, cold pink blush, white...
        depth: 4,
        vein: -2,
        answered: 6,
      );
      expect(r.colorType, 'Зима');
      expect(r.undertone, 'Холодный');
    });

    test('warm answers plus green veins give Осень and a warm undertone', () {
      final r = ColorTestService.compute(
        warm: 4,
        depth: 6,
        vein: 2,
        answered: 8,
      );
      expect(r.colorType, 'Осень');
      expect(r.undertone, 'Тёплый');
    });
  });

  group('the test result screen never leaves a black page', () {
    for (final fromProfile in [false, true]) {
      testWidgets(
        'Готово ${fromProfile ? 'with' : 'without'} the profile under it',
        (t) async {
          t.view.physicalSize = const Size(1080, 2400);
          t.view.devicePixelRatio = 3;
          addTearDown(t.view.reset);
          final helper = DatabaseHelper(path: inMemoryDatabasePath);
          addTearDown(() => t.runAsync(helper.close));
          await t.runAsync(() => UserRepository(helper).setCurrentUser(1));
          await t.pumpWidget(CosmetixApp(helper: helper));
          await pumpUntil(t, find.text('Кабинет'));
          await _settle(t);

          final nav = t.state<NavigatorState>(find.byType(Navigator).first);
          if (fromProfile) {
            nav.pushNamed(AppRoutes.beautyProfile);
            await _settle(t);
          }
          // the test is started from the cabinet / home, as in the real app
          nav.pushNamed(AppRoutes.colorTest);
          await _settle(t);
          nav.pushReplacementNamed(
            AppRoutes.colorResult,
            arguments: BeautyResultArgs(
              profile: BeautyProfile.fromLabels(
                skinType: 'Сухая',
                skinTone: 'Светлый',
                undertone: 'Тёплый',
                colorType: 'Весна',
              ),
            ),
          );
          await _settle(t);
          // the button is at the bottom of a long list
          await t.scrollUntilVisible(
            find.text('Готово'),
            400,
            scrollable: find.byType(Scrollable).last,
          );
          await t.tap(find.text('Готово'));
          await _settle(t);

          // the result screen is gone and a real screen is under it: the
          // profile (opened from there) or the first screen with the bottom bar.
          // (A flutter Navigator never pops its very first route, so this
          // guards the intent: "Готово" must land on a visible screen.)
          expect(find.text('Готово'), findsNothing);
          expect(find.byType(Navigator), findsWidgets);
          final nav2 = t.state<NavigatorState>(find.byType(Navigator).first);
          expect(
            nav2.canPop() || find.text('Кабинет').evaluate().isNotEmpty,
            isTrue,
          );
          // some real screen is on top (never an empty navigator)
          expect(find.byType(Scaffold), findsWidgets);
        },
      );
    }
  });
}
