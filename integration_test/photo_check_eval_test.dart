import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:cosmetix/services/photo_check/photo_check.dart';

/// The local photo check with the REAL decoder and the REAL face mesh, on a
/// simulator or a phone. It measures; the photos are not in the repository
/// (they show real people): pass the folders with
///
///   flutter test integration_test/photo_check_eval_test.dart -d DEVICE \
///     --dart-define=EVAL_DIR=/path/to/photos --dart-define=EVAL_OUT=/path/to/result.json \
///     --dart-define=EXIF_DIR=/path/to/o1_o3_o6_o8_jpegs
///
/// EVAL_DIR / EVAL_OUT: one verdict and the metrics per photo (compared with the
/// Python stand by tools/eval/compare_dart_python.py). EXIF_DIR: the same face
/// stored with EXIF orientation 1, 3, 6 and 8; the check must see the same face.
/// Without the defines the test is skipped. Numbers are for THAT device and a
/// debug build, not for release speed on a phone.
const _dir = String.fromEnvironment('EVAL_DIR');
const _out = String.fromEnvironment('EVAL_OUT');
const _exifDir = String.fromEnvironment('EXIF_DIR');

List<File> _jpgs(String dir) =>
    Directory(dir).listSync().whereType<File>().where((f) {
      final p = f.path.toLowerCase();
      return p.endsWith('.jpg') || p.endsWith('.jpeg') || p.endsWith('.png');
    }).toList()..sort((a, b) => a.path.compareTo(b.path));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('damaged files are refused as unreadable, nothing crashes', (
    t,
  ) async {
    final check = PhotoCheck(MediaPipePhotoFaceFinder());
    addTearDown(check.dispose);
    final good = _dir.isEmpty ? null : _jpgs(_dir).first.readAsBytesSync();
    final cases = <String, Uint8List>{
      'empty': Uint8List(0),
      'text': Uint8List.fromList(utf8.encode('this is not an image')),
      'random': Uint8List.fromList(List.generate(4096, (i) => (i * 37) % 251)),
      'jpeg header only': Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 16]),
      if (good != null) 'truncated jpeg': good.sublist(0, good.length ~/ 3),
      if (good != null)
        'jpeg with a broken middle': Uint8List.fromList([
          ...good.sublist(0, 400),
          ...List.filled(good.length - 400, 0),
        ]),
    };
    for (final e in cases.entries) {
      final r = await t.runAsync(() => check.run(e.value));
      debugPrint(
        'PC_DAMAGED ${e.key} -> ${r!.verdict.accepted ? 'ACCEPTED' : r.verdict.issues.map((i) => i.name)}',
      );
      expect(r.verdict.accepted, isFalse, reason: e.key);
    }
  });

  testWidgets('the evaluation photos: verdict and metrics', (t) async {
    if (_dir.isEmpty || _out.isEmpty) {
      markTestSkipped('EVAL_DIR / EVAL_OUT are not set');
      return;
    }
    final check = PhotoCheck(MediaPipePhotoFaceFinder());
    addTearDown(check.dispose);
    final rows = <Map<String, Object?>>[];
    final times = <int>[];
    for (final f in _jpgs(_dir)) {
      final name = f.uri.pathSegments.last.split('.').first;
      final sw = Stopwatch()..start();
      final r = await t.runAsync(() => check.run(f.readAsBytesSync()));
      sw.stop();
      times.add(sw.elapsedMilliseconds);
      final v = r!.verdict;
      rows.add({
        'photo': name,
        'verdict': v.level.name,
        'issues': [for (final i in v.issues) i.name],
        'ms': sw.elapsedMilliseconds,
        if (r.metrics != null) 'metrics': r.metrics!.toJson(),
      });
      debugPrint(
        'PC_ROW $name ${rows.last['verdict']} ${rows.last['issues']} ${sw.elapsedMilliseconds}ms',
      );
    }
    File(_out)
      ..createSync(recursive: true)
      ..writeAsStringSync(const JsonEncoder.withIndent(' ').convert(rows));
    times.sort();
    debugPrint(
      'PC_TIME photos=${times.length} median=${times[times.length ~/ 2]}ms max=${times.last}ms',
    );
  });

  testWidgets('EXIF orientation 1/3/6/8 gives the same face', (t) async {
    if (_exifDir.isEmpty) {
      markTestSkipped('EXIF_DIR is not set');
      return;
    }
    final check = PhotoCheck(MediaPipePhotoFaceFinder());
    addTearDown(check.dispose);
    final results = <String, PhotoCheckResult>{};
    for (final f in _jpgs(_exifDir)) {
      final name = f.uri.pathSegments.last.split('.').first;
      results[name] = (await t.runAsync(() => check.run(f.readAsBytesSync())))!;
      final m = results[name]!.metrics;
      debugPrint(
        'PC_EXIF $name faces=${m?.faceCount} face_px=${m?.facePx} yaw=${m?.yawOffset} roll=${m?.rollDeg} '
        'verdict=${results[name]!.verdict.accepted}',
      );
    }
    expect(results, isNotEmpty);
    final base = results.values.first.metrics;
    expect(base, isNotNull, reason: 'a face must be found in the first file');
    for (final e in results.entries) {
      final m = e.value.metrics;
      expect(m, isNotNull, reason: '${e.key}: face not found (orientation?)');
      expect(m!.faceCount, 1, reason: e.key);
      // same face, same size and the same turn, whatever the stored orientation
      expect(m.facePx, closeTo(base!.facePx, base.facePx * 0.08), reason: e.key);
      expect(m.yawOffset, closeTo(base.yawOffset, 0.06), reason: e.key);
      expect(m.rollDeg.abs(), lessThan(8), reason: '${e.key}: upright face');
    }
  });
}
