import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/app.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/database/seed_data.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/services/ingredient_scan/ingredient_ocr.dart';
import 'widget_test.dart' show pumpUntil;

class FakeOcr implements IngredientOcr {
  String text = '';
  Object? error;
  final paths = <String>[];

  @override
  Future<String> recognize(String imagePath) async {
    paths.add(imagePath);
    if (error != null) throw error!;
    return text;
  }
}

class FakePhotos implements ScanPhotoSource {
  Object? error;
  String? path = 'tool/sample_labels/label_en.png';
  final cameraRequests = <bool>[];

  @override
  Future<String?> pick({required bool camera}) async {
    cameraRequests.add(camera);
    if (error != null) throw error!;
    return path;
  }
}

Future<void> _settle(WidgetTester t, [int rounds = 6]) async {
  for (var i = 0; i < rounds; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// The check button is below the fold on small screens: scroll to it first.
Future<void> _tapCheck(WidgetTester t) async {
  final button = find.text('Проверить по чёрному списку');
  await t.scrollUntilVisible(
    button,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await t.tap(button);
  await _settle(t, 2);
}

/// Scrolls the list (down, then up) until [finder] is built and on screen.
Future<void> _see(WidgetTester t, Finder finder) async {
  if (finder.hitTestable().evaluate().isNotEmpty) return;
  final list = find.byType(Scrollable).first;
  try {
    await t.scrollUntilVisible(finder, 200, scrollable: list);
  } on StateError {
    await t.scrollUntilVisible(finder, -200, scrollable: list);
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Future<(FakeOcr, FakePhotos)> open(WidgetTester t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final helper = DatabaseHelper(path: inMemoryDatabasePath);
    addTearDown(() => t.runAsync(helper.close));
    final ocr = FakeOcr();
    final photos = FakePhotos();
    await t.pumpWidget(
      CosmetixApp(helper: helper, ocr: ocr, photoSource: photos),
    );
    await pumpUntil(t, find.text('Добро пожаловать'));
    await t.enterText(find.byType(TextFormField).at(0), SeedData.demoEmail);
    await t.enterText(find.byType(TextFormField).at(1), SeedData.demoPassword);
    await t.tap(find.text('Войти'));
    await pumpUntil(t, find.text('Кабинет'));
    await _settle(t);
    final ctx = t.element(find.byType(Scaffold).first);
    Navigator.of(ctx).pushNamed(AppRoutes.scan);
    await _settle(t);
    return (ocr, photos);
  }

  testWidgets('a photo is read, can be corrected and is checked', (t) async {
    final (ocr, photos) = await open(t);
    ocr.text =
        'INGREDIENTS: Aqua, Glycerin, Sodium Laureth\nSulfate, Methylparaben, Dimethicone, Parfum.\nDirections: rinse well.';

    await t.tap(find.text('Выбрать фото из галереи'));
    await _settle(t);
    expect(photos.cameraRequests, [false]); // the gallery, not the camera
    expect(ocr.paths, ['tool/sample_labels/label_en.png']);

    // the recognized list is shown for checking and fixing
    final field = find.byType(TextField);
    expect(
      (t.widget(field) as TextField).controller!.text,
      'Aqua, Glycerin, Sodium Laureth Sulfate, Methylparaben, Dimethicone, Parfum',
    );
    expect(find.textContaining('Состав распознан'), findsOneWidget);

    await _tapCheck(t);
    await _see(t, find.text('Результат'));
    // demo user: parabens, sulfates and formaldehyde are on; silicones are off
    await _see(t, find.text('Найдено совпадений с чёрным списком: 2'));
    await _see(t, find.textContaining('относится к группе «Парабены»'));
    await _see(t, find.textContaining('группе «Сульфаты'));
    expect(find.textContaining('Силиконы'), findsNothing);
    await _see(t, find.text('Все компоненты (6)'));

    // the user fixes the list: no hits any more
    await _see(t, field);
    await t.enterText(field, 'Aqua, Glycerin, Tocopherol');
    await _tapCheck(t);
    await _see(t, find.text('Совпадений с вашим чёрным списком не найдено.'));
    await _see(t, find.textContaining('не гарантия'));
    expect(t.takeException(), isNull);
  });

  testWidgets('camera unavailable (simulator) is explained, not a crash', (
    t,
  ) async {
    final (_, photos) = await open(t);
    photos.error = const PhotoUnavailable('no camera');
    await t.tap(find.text('Сделать снимок'));
    await _settle(t, 2);
    expect(photos.cameraRequests, [true]);
    expect(find.textContaining('Камера недоступна'), findsOneWidget);
    expect(t.takeException(), isNull);
    await _settle(t, 20); // let the snack bar go away
  });

  testWidgets('no OCR on this device: manual entry still works', (t) async {
    final (ocr, _) = await open(t);
    ocr.error = const OcrUnavailable('nope');
    await t.tap(find.text('Выбрать фото из галереи'));
    await _settle(t);
    expect(find.textContaining('Введите состав вручную'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'Aqua, Propylparaben');
    await _tapCheck(t);
    await _see(t, find.text('Найдено совпадений с чёрным списком: 1'));
  });

  testWidgets('an unreadable photo gives advice and keeps the field empty', (
    t,
  ) async {
    final (ocr, _) = await open(t);
    ocr.text = '  \n ';
    await t.tap(find.text('Выбрать фото из галереи'));
    await _settle(t);
    expect(find.textContaining('Не удалось прочитать состав'), findsOneWidget);
    expect(
      (t.widget(find.byType(TextField)) as TextField).controller!.text,
      '',
    );
    // checking an empty field warns instead of showing a fake result
    await _tapCheck(t);
    expect(find.text('Введите состав или выберите фото'), findsOneWidget);
    expect(find.text('Результат'), findsNothing);
    await _settle(t, 20);
  });

  testWidgets('cancelling the picker changes nothing', (t) async {
    final (ocr, photos) = await open(t);
    photos.path = null;
    await t.tap(find.text('Выбрать фото из галереи'));
    await _settle(t, 2);
    expect(ocr.paths, isEmpty);
    expect(find.textContaining('Состав распознан'), findsNothing);
  });
}
