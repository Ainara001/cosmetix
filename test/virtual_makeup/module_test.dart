import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/app.dart';
import 'package:cosmetix/core/i18n/translations_en.dart';
import 'package:cosmetix/core/i18n/translations_kk.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/repositories/user_repository.dart';
import 'package:cosmetix/routes/app_routes.dart';

import '../widget_test.dart' show pumpUntil;

List<File> _moduleFiles() => [
  for (final e in Directory(
    'lib/features/virtual_makeup',
  ).listSync(recursive: true))
    if (e is File && e.path.endsWith('.dart')) e,
];

String _withoutComments(String s) => s.replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('the module is self-contained', () {
    test(
      'it does not touch the database, the catalog, the server or the skin analysis',
      () {
        const forbidden = [
          'package:cosmetix/database',
          'package:cosmetix/repositories',
          'package:cosmetix/providers',
          'package:cosmetix/models',
          'package:cosmetix/services',
          'package:sqflite',
          'dart:io', // only photo_io.dart may use files (checked below)
        ];
        for (final f in _moduleFiles()) {
          final src = _withoutComments(f.readAsStringSync());
          for (final bad in forbidden) {
            if (bad == 'dart:io' && f.path.endsWith('photo_io.dart')) continue;
            expect(
              src.contains(bad),
              isFalse,
              reason: '${f.path} imports $bad',
            );
          }
        }
      },
    );

    // The shared face geometry (lib/core/face: pure geometry and the on-phone
    // MediaPipe adapter) is allowed too: the try-on must see the same mesh
    // as the photo check and the smart camera.
    test('the only app code it uses is the shared look and feel', () {
      final allowed = RegExp(
        r"package:cosmetix/(core/face/[a-z_]+|core/i18n/tr|core/theme/app_colors|core/theme/app_text_styles|core/utils/ui_helpers|widgets/app_card|widgets/custom_button|widgets/pill_segments|widgets/common_widgets|widgets/page_scaffold)\.dart",
      );
      for (final f in _moduleFiles()) {
        for (final m in RegExp(
          r"import 'package:cosmetix/[^']+'",
        ).allMatches(f.readAsStringSync())) {
          final line = m.group(0)!;
          expect(allowed.hasMatch(line), isTrue, reason: '${f.path}: $line');
        }
      }
    });

    test('nothing in the module saves a photo or sends one anywhere', () {
      for (final f in _moduleFiles()) {
        final src = _withoutComments(f.readAsStringSync());
        for (final bad in [
          'writeAsBytes',
          'HttpClient',
          'package:http',
          'Socket',
          'saveImage',
          'ImageGallerySaver',
        ]) {
          expect(src.contains(bad), isFalse, reason: '${f.path} uses $bad');
        }
      }
    });

    test(
      'no smoothing: the engine has no blur, denoise or retouch of the photo',
      () {
        for (final name in [
          'color_transfer_backend.dart',
          'makeup_backend.dart',
        ]) {
          final src = _withoutComments(
            File('lib/features/virtual_makeup/engine/$name').readAsStringSync(),
          );
          for (final bad in [
            'blur',
            'denoise',
            'smooth',
            'retouch',
            'ImageFilter',
            'bilateral',
          ]) {
            expect(
              src.toLowerCase().contains(bad.toLowerCase()),
              isFalse,
              reason: '$name mentions $bad',
            );
          }
        }
      },
    );
  });

  test('every Russian string of the module is translated (EN and KK)', () {
    final seen = <String>{};
    for (final f in [..._moduleFiles()]) {
      final src = _withoutComments(f.readAsStringSync());
      for (final m in RegExp(r"'((?:[^'\\\n]|\\.)*)'").allMatches(src)) {
        final t = m.group(1)!;
        if (RegExp('[А-Яа-яЁё]').hasMatch(t)) {
          seen.add(t.replaceAll(r"\'", "'"));
        }
      }
    }
    expect(seen.length, greaterThan(40));
    for (final k in seen) {
      expect(translationsEn.containsKey(k), isTrue, reason: 'EN: $k');
      expect(translationsKk.containsKey(k), isTrue, reason: 'KK: $k');
      for (final ph in RegExp(r'\{\w+\}').allMatches(k).map((m) => m[0]!)) {
        expect(translationsEn[k], contains(ph), reason: 'EN $ph in $k');
        expect(translationsKk[k], contains(ph), reason: 'KK $ph in $k');
      }
    }
  });

  testWidgets('the profile menu opens the try-on screen', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final h = DatabaseHelper(path: inMemoryDatabasePath);
    addTearDown(() => t.runAsync(h.close));
    await t.runAsync(() => UserRepository(h).setCurrentUser(1));
    await t.pumpWidget(CosmetixApp(helper: h));
    await pumpUntil(t, find.text('Кабинет'));
    for (var i = 0; i < 8; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await t.pump(const Duration(milliseconds: 100));
    }
    // a tall screen: the whole profile menu is on it, no scrolling needed
    t.view.physicalSize = const Size(1080, 5200);
    await t.tap(find.text('Кабинет'));
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('Виртуальная примерка'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('vm-disclaimer')), findsOneWidget);
    expect(find.byKey(const Key('vm-picker')), findsOneWidget);
    expect(AppRoutes.virtualMakeup, '/virtual-makeup');
  });
}
