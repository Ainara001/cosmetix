import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart' show inMemoryDatabasePath;

import 'package:cosmetix/core/theme/app_theme.dart';
import 'package:cosmetix/database/catalog_data.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/features/virtual_makeup/landmarks/mediapipe_landmark_provider.dart';
import 'package:cosmetix/features/virtual_makeup/ui/photo_io.dart';
import 'package:cosmetix/features/virtual_makeup/ui/virtual_makeup_controller.dart';
import 'package:cosmetix/features/virtual_makeup/virtual_makeup.dart';
import 'package:cosmetix/repositories/try_on_repository.dart';

/// Speed, memory and smoothness of the try-on with the REAL face mesh and the
/// catalog. The numbers belong to the device and the build mode they were made
/// on: a debug build on a simulator says little about a phone. To measure a
/// phone, run the same file on it (see docs/real-skin-makeup-stage2-report.md).
///
///   flutter test integration_test/virtual_makeup_perf_test.dart -d DEVICE \
///     --dart-define=VM_PHOTO=/path/to/face.jpg
const _photo = String.fromEnvironment('VM_PHOTO');

class _FilePhotos implements MakeupPhotoSource {
  _FilePhotos(this.bytes);
  final Uint8List bytes;
  @override
  Future<Uint8List?> pick({required bool camera}) async => bytes;
}

double _median(List<double> v) {
  final s = [...v]..sort();
  return s[s.length ~/ 2];
}

String _stats(List<double> v) =>
    'median ${_median(v).toStringAsFixed(1)} ms, '
    'max ${(([...v]..sort()).last).toStringAsFixed(1)} ms (n=${v.length})';

String _mode() => kDebugMode ? 'DEBUG' : (kProfileMode ? 'PROFILE' : 'RELEASE');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('time, memory and frames of the catalog try-on', (t) async {
    if (_photo.isEmpty) {
      markTestSkipped('VM_PHOTO is not set');
      return;
    }
    final bytes = File(_photo).readAsBytesSync();
    final helper = DatabaseHelper(path: inMemoryDatabasePath);
    await helper.database;
    final catalog = await CatalogData.load();
    int idOf(String name) =>
        catalog.products.indexWhere((p) => p.name == name) + 1;
    final berry = idOf('Ink Mood Glowy Tint 30 Happy Berry');
    int rss() => ProcessInfo.currentRss;
    final rss0 = rss();

    // ---------------------------------------------------------- controller
    final provider = MediaPipeLandmarkProvider();
    final c = VirtualMakeupController(
      landmarks: provider,
      catalog: TryOnRepository(helper),
    );
    await c.startWith(berry);

    // the result image changes when a render finishes
    Future<double> untilNewResult(void Function() action) async {
      final before = c.resultImage;
      final done = Completer<void>();
      void listener() {
        if (!done.isCompleted && !identical(c.resultImage, before)) {
          done.complete();
        }
      }

      c.addListener(listener);
      final sw = Stopwatch()..start();
      action();
      await done.future.timeout(const Duration(seconds: 20));
      sw.stop();
      c.removeListener(listener);
      return sw.elapsedMicroseconds / 1000;
    }

    final sw = Stopwatch()..start();
    await c.loadPhoto(bytes);
    final firstLoad = sw.elapsedMicroseconds / 1000;
    expect(c.status, MakeupStatus.ready);
    debugPrint(
      'PERF photo ${c.face!.image.width}x${c.face!.image.height}: '
      'photo -> first result (detect + prepare + render + picture) '
      '${firstLoad.toStringAsFixed(0)} ms (first call, cold)',
    );
    final loads = <double>[];
    for (var i = 0; i < 5; i++) {
      final s = Stopwatch()..start();
      await c.loadPhoto(bytes);
      loads.add(s.elapsedMicroseconds / 1000);
    }
    debugPrint('PERF photo -> result again: ${_stats(loads)}');

    await c.applyItem(c.lineShades.first); // warm the caches
    final shades = [for (final s in c.lineShades) s];
    final switchTimes = <double>[];
    for (var i = 0; i < 20; i++) {
      final next = shades[i % shades.length];
      if (c.items[MakeupZone.lips] == next) continue;
      switchTimes.add(await untilNewResult(() => c.applyItem(next)));
    }
    debugPrint('PERF shade switch -> new picture: ${_stats(switchTimes)}');

    final sliderTimes = <double>[];
    for (var i = 0; i < 20; i++) {
      final k = 0.2 + (i % 8) * 0.1;
      sliderTimes.add(
        await untilNewResult(
          () => c.setZone(MakeupZone.lips, c.look.lips.copyWith(intensity: k)),
        ),
      );
    }
    debugPrint('PERF intensity change -> new picture: ${_stats(sliderTimes)}');

    // the protection brush: strokes on a 820x1024-class photo
    final strokeTimes = <double>[];
    final fw = c.face!.points.faceWidth;
    final centre = c.face!.points[1];
    c.strokeStart(centre, fw * 0.03, erase: false);
    for (var i = 0; i < 60; i++) {
      final s = Stopwatch()..start();
      c.strokeMove(centre + Offset(i * 3.0, i * 1.0), fw * 0.03, erase: false);
      strokeTimes.add(s.elapsedMicroseconds / 1000);
    }
    c.strokeEnd();
    debugPrint('PERF brush move (the call itself): ${_stats(strokeTimes)}');

    final sg = Stopwatch()..start();
    c.suggest();
    debugPrint(
      'PERF blemish suggestion (runs on the UI thread): '
      '${(sg.elapsedMicroseconds / 1000).toStringAsFixed(0)} ms',
    );
    final rssAfter = rss();
    c.dispose();

    // ------------------------------------------------------------- frames
    final screenHelper = helper;
    final provider2 = MediaPipeLandmarkProvider();
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: VirtualMakeupScreen(
          landmarks: provider2,
          photos: _FilePhotos(bytes),
          catalog: TryOnRepository(screenHelper),
          productId: berry,
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(find.byKey(const Key('vm-gallery')));
    for (
      var i = 0;
      i < 100 && find.byKey(const Key('vm-photo')).evaluate().isEmpty;
      i++
    ) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('vm-photo')), findsOneWidget);
    await t.pump(const Duration(milliseconds: 500));

    // drag the intensity slider back and forth, and switch shades, while the
    // frame timings are recorded
    final slider = find.byKey(const Key('vm-item-slider-lips'));
    await t.scrollUntilVisible(
      slider,
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await binding.watchPerformance(() async {
      for (var i = 0; i < 6; i++) {
        await t.drag(slider, const Offset(120, 0));
        await t.pump(const Duration(milliseconds: 100));
        await t.drag(slider, const Offset(-120, 0));
        await t.pump(const Duration(milliseconds: 100));
      }
    }, reportKey: 'slider_drag');
    final rep = binding.reportData?['slider_drag'] as Map<String, dynamic>?;
    debugPrint(
      'PERF frames while dragging the intensity slider (${_mode()}): '
      '${rep == null ? 'no data' : rep.entries.map((e) => '${e.key}=${e.value}').join(', ')}',
    );

    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 200));
    await provider2.dispose();
    await provider.dispose();
    debugPrint(
      'PERF memory (RSS of the process, ${_mode()}): start '
      '${(rss0 / 1048576).round()} MB, after the controller run '
      '${(rssAfter / 1048576).round()} MB, end ${(rss() / 1048576).round()} MB',
    );
    debugPrint(
      'PERF device: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    );
    await helper.close();
  }, timeout: const Timeout(Duration(minutes: 10)));
}
