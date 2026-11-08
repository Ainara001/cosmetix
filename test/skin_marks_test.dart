import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/core/beauty/beauty_codes.dart';
import 'package:cosmetix/core/face/face_geometry.dart';
import 'package:cosmetix/core/face/face_points.dart';
import 'package:cosmetix/core/face/face_zones.dart';
import 'package:cosmetix/core/face/mean_mesh.dart';
import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/theme/app_theme.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/models/skin_marks.dart';
import 'package:cosmetix/providers/auth_provider.dart';
import 'package:cosmetix/providers/cart_provider.dart';
import 'package:cosmetix/providers/nav_provider.dart';
import 'package:cosmetix/repositories/cart_repository.dart';
import 'package:cosmetix/repositories/skin_marks_repository.dart';
import 'package:cosmetix/repositories/user_repository.dart';
import 'package:cosmetix/screens/care/skin_marks_screen.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  setUp(() => currentLang = AppLang.ru);

  group('marks -> profile concerns', () {
    test('only what a mark supports; scars, pores, texture map to nothing', () {
      expect(SkinFeature.acne.concerns, {SkinConcern.acne});
      expect(SkinFeature.comedones.concerns, {SkinConcern.acne});
      expect(SkinFeature.postAcne.concerns, {
        SkinConcern.acne,
        SkinConcern.pigmentation,
      });
      expect(SkinFeature.pigmentation.concerns, {SkinConcern.pigmentation});
      expect(SkinFeature.redness.concerns, {SkinConcern.sensitivity});
      for (final f in [
        SkinFeature.scars,
        SkinFeature.pores,
        SkinFeature.texture,
      ]) {
        expect(f.concerns, isEmpty, reason: '$f');
      }
    });

    test('a set of marks: concerns, per zone, and the dermatologist note', () {
      final m = SkinMarks({
        SkinZoneMark(FaceZone.chin, SkinFeature.acne),
        SkinZoneMark(FaceZone.cheekLeft, SkinFeature.postAcne),
        SkinZoneMark(FaceZone.cheekLeft, SkinFeature.scars),
      });
      expect(m.concerns, {SkinConcern.acne, SkinConcern.pigmentation});
      expect(m.on(FaceZone.cheekLeft), {
        SkinFeature.postAcne,
        SkinFeature.scars,
      });
      expect(m.on(FaceZone.nose), isEmpty);
      expect(m.suggestsDermatologist, isTrue);
      expect(SkinMarks.empty.suggestsDermatologist, isFalse);
    });

    test('codes round-trip', () {
      for (final f in SkinFeature.values) {
        expect(SkinFeature.fromCode(f.code), f);
      }
    });
  });

  group('storage', () {
    late DatabaseHelper helper;
    late int userId;
    setUp(() async {
      helper = DatabaseHelper(path: inMemoryDatabasePath);
      userId = (await UserRepository(helper).register(
        firstName: 'Тест',
        email: 'marks${DateTime.now().microsecondsSinceEpoch}@test.kz',
        password: 'Passw0rd1',
      )).id;
    });
    tearDown(() => helper.close());

    test('the schema is at version 19 with the marks table', () async {
      expect(DatabaseHelper.dbVersion, 19);
      final db = await helper.database;
      final cols = await db.rawQuery('PRAGMA table_info(skin_zone_marks)');
      expect(
        cols.map((r) => r['name']),
        containsAll(['user_id', 'zone', 'feature', 'marked_at']),
      );
    });

    test(
      'replace and read back; replacing again removes what was unmarked',
      () async {
        final repo = SkinMarksRepository(helper);
        expect((await repo.current(userId)).isEmpty, isTrue);
        await repo.replace(userId, {
          const SkinZoneMark(FaceZone.chin, SkinFeature.acne),
          const SkinZoneMark(FaceZone.nose, SkinFeature.pores),
        });
        var now = await repo.current(userId);
        expect(now.marks, hasLength(2));
        expect(now.markedAt, isNotNull);
        await repo.replace(userId, {
          const SkinZoneMark(FaceZone.chin, SkinFeature.acne),
        });
        now = await repo.current(userId);
        expect(now.marks, {
          const SkinZoneMark(FaceZone.chin, SkinFeature.acne),
        });
      },
    );

    test('the database refuses unknown codes and duplicates', () async {
      final db = await helper.database;
      Future<void> put(String zone, String feature) => db.insert(
        'skin_zone_marks',
        {'user_id': userId, 'zone': zone, 'feature': feature, 'marked_at': 1},
      );
      await put('chin', 'acne');
      await expectLater(put('ear', 'acne'), throwsA(isA<DatabaseException>()));
      await expectLater(
        put('chin', 'cancer'),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(put('chin', 'acne'), throwsA(isA<DatabaseException>()));
    });

    test('marks belong to one person and go with the account', () async {
      final repo = SkinMarksRepository(helper);
      final other = (await UserRepository(helper).register(
        firstName: 'Другой',
        email: 'other${DateTime.now().microsecondsSinceEpoch}@test.kz',
        password: 'Passw0rd1',
      )).id;
      await repo.replace(userId, {
        const SkinZoneMark(FaceZone.chin, SkinFeature.acne),
      });
      expect((await repo.current(other)).isEmpty, isTrue);
      final db = await helper.database;
      await db.delete('users', where: 'id = ?', whereArgs: [userId]);
      expect(await db.query('skin_zone_marks'), isEmpty);
    });

    test('"delete all data" also deletes the marks', () async {
      await SkinMarksRepository(helper).replace(userId, {
        const SkinZoneMark(FaceZone.nose, SkinFeature.redness),
      });
      await helper.resetDemoData();
      expect(await (await helper.database).query('skin_zone_marks'), isEmpty);
    });
  });

  test('an existing v18 install upgrades to v19 and keeps its data', () async {
    final dir = Directory.systemTemp.createTempSync('cosmetix_v19');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/app.db';
    // a database as v18 builds left it: the full v18 schema, one user
    final v18 = DatabaseHelper(path: path);
    final db0 = await v18.database;
    await db0.execute('DROP TABLE skin_zone_marks');
    await db0.setVersion(18);
    final id = await db0.insert('users', {
      'first_name': 'Айгерим',
      'email': 'v18@test.kz',
      'password_hash': 'x',
      'created_at': 1,
      'updated_at': 1,
    });
    final users = (await db0.query('users')).length;
    await v18.close();

    final v19 = DatabaseHelper(path: path);
    final db = await v19.database;
    addTearDown(v19.close);
    expect(await db.getVersion(), 19);
    expect((await db.query('users')).length, users);
    await SkinMarksRepository(
      v19,
    ).replace(id, {const SkinZoneMark(FaceZone.forehead, SkinFeature.texture)});
    expect((await SkinMarksRepository(v19).current(id)).marks, hasLength(1));
  });

  group('the screen', () {
    Future<({DatabaseHelper helper, AuthProvider auth})> open(
      WidgetTester t, {
      PhotoFaceLocator? locate,
      Future<Uint8List?> Function()? pick,
      Size size = const Size(
        390,
        1700,
      ), // tall: the lazy list builds everything
      double text = 1,
    }) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = text;
      addTearDown(t.view.reset);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      final helper = DatabaseHelper(path: inMemoryDatabasePath);
      addTearDown(() => t.runAsync(helper.close));
      final users = UserRepository(helper);
      await t.runAsync(() async {
        final u = await users.register(
          firstName: 'Тест',
          email: 'screen${DateTime.now().microsecondsSinceEpoch}@test.kz',
          password: 'Passw0rd1',
        );
        await users.setCurrentUser(u.id);
      });
      final auth = AuthProvider(users);
      await t.runAsync(auth.restoreSession);
      await t.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider(create: (_) => NavProvider()),
            ChangeNotifierProvider(
              create: (_) => CartProvider(CartRepository(helper)),
            ),
            Provider<SkinMarksRepository>.value(
              value: SkinMarksRepository(helper),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: SkinMarksScreen(locate: locate, pickPhoto: pick),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await t.pump(const Duration(milliseconds: 50));
      }
      return (helper: helper, auth: auth);
    }

    testWidgets('choose a zone, mark features, save: stored and mapped', (
      t,
    ) async {
      final o = await open(t);
      await t.tap(find.text('Подбородок'));
      await t.pump();
      await t.tap(find.byKey(const Key('feature-acne')));
      await t.pump();
      await t.tap(find.text('Нос'));
      await t.pump();
      await t.tap(find.byKey(const Key('feature-pores')));
      await t.pump();
      expect(
        find.textContaining('В подборе ухода учтём: Акне и высыпания'),
        findsOneWidget,
      );
      await t.ensureVisible(find.text('Сохранить отметки'));
      await t.tap(find.text('Сохранить отметки'));
      for (var i = 0; i < 5; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await t.pump(const Duration(milliseconds: 50));
      }
      final saved = await t.runAsync(
        () => SkinMarksRepository(o.helper).current(o.auth.userId),
      );
      expect(saved!.marks, {
        const SkinZoneMark(FaceZone.chin, SkinFeature.acne),
        const SkinZoneMark(FaceZone.nose, SkinFeature.pores),
      });
    });

    testWidgets('tapping the picture selects the zone under the finger', (
      t,
    ) async {
      await open(t);
      final view = find.byKey(const Key('face-view'));
      final box = t.getRect(view);
      // the schematic face's chin label point, mapped like the screen does
      final face = FaceGeometry(
        FacePoints(meanFace(const Offset(150, 185), 250)),
        imageSize: const Size(300, 390),
      );
      final p = FaceZones.of(face).labelPoint(FaceZone.chin);
      final scale = box.width / 300;
      await t.tapAt(box.topLeft + p * scale);
      await t.pump();
      await t.tap(find.byKey(const Key('feature-redness')));
      await t.pump();
      expect(find.text('Подбородок · 1'), findsOneWidget);
    });

    testWidgets('scars: the dermatologist note, no care concern', (t) async {
      await open(t);
      await t.tap(find.byKey(const Key('feature-scars')));
      await t.pump();
      expect(find.textContaining('к дерматологу'), findsWidgets);
      expect(find.textContaining('В подборе ухода учтём'), findsNothing);
    });

    testWidgets('own photo: no single face -> a message, the diagram stays', (
      t,
    ) async {
      await open(t, pick: () async => Uint8List(4), locate: (_) async => null);
      await t.tap(find.text('Отметить на своём фото'));
      for (var i = 0; i < 4; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(find.textContaining('нужно одно лицо'), findsOneWidget);
      expect(find.text('Отметить на своём фото'), findsOneWidget);
    });

    testWidgets(
      'own photo with a face: zones on it, then back to the diagram',
      (t) async {
        final img = await t.runAsync(() async {
          final r = ui.PictureRecorder();
          Canvas(r).drawColor(const Color(0xFFC8A890), BlendMode.src);
          return r.endRecording().toImage(600, 800);
        });
        await open(
          t,
          pick: () async => Uint8List(4),
          locate: (_) async => (
            image: img!,
            face: FaceGeometry(
              FacePoints(meanFace(const Offset(300, 380), 320)),
              imageSize: const Size(600, 800),
            ),
          ),
        );
        await t.tap(find.text('Отметить на своём фото'));
        for (var i = 0; i < 4; i++) {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await t.pump(const Duration(milliseconds: 50));
        }
        expect(
          find.textContaining('не сохраняется и никуда не отправляется'),
          findsOneWidget,
        );
        await t.tap(find.text('Вернуться к схеме'));
        await t.pump();
        expect(find.text('Отметить на своём фото'), findsOneWidget);
      },
    );

    for (final text in [1.0, 1.5, 2.0]) {
      testWidgets('iPhone SE with ${text}x text: no overflow', (t) async {
        await open(t, size: const Size(375, 667), text: text);
        expect(t.takeException(), isNull);
        await t.scrollUntilVisible(find.byKey(const Key('feature-acne')), 200);
        await t.tap(find.byKey(const Key('feature-acne')));
        await t.pump();
        expect(t.takeException(), isNull);
      });
    }
  });

  test('every string of the zones and marks is translated (EN, KK)', () {
    final texts = [
      for (final z in FaceZone.values) z.label,
      for (final f in SkinFeature.values) f.label,
      'Особенности кожи',
      'Выберите зону и отметьте, что вы на ней видите.',
      'Отметить на своём фото',
      'Вернуться к схеме',
      'Фото только на экране: оно не сохраняется и никуда не отправляется.',
      'В подборе ухода учтём: {v}',
      'Рубцы косметика не убирает: с ними лучше обратиться к дерматологу.',
      'Сохранить отметки',
      'Это ваши наблюдения, а не диагноз: приложение не определяет акне, рубцы или пигментацию по фото. Если высыпаний много, они болезненные или оставляют следы, обратитесь к дерматологу.',
      'Схема лица: выберите зону кнопками ниже или касанием',
      'На фото нужно одно лицо, крупно и анфас. Можно отмечать на схеме.',
      'Не удалось открыть фото. Можно отмечать на схеме.',
      'Отметки сохранены',
      'Отметить особенности кожи',
    ];
    for (final lang in [AppLang.en, AppLang.kk]) {
      currentLang = lang;
      expect(
        [
          for (final s in texts)
            if (tr(s) == s) s,
        ],
        isEmpty,
        reason: '$lang',
      );
    }
    currentLang = AppLang.ru;
  });
}
