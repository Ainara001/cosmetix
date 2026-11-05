import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:cosmetix/features/virtual_makeup/domain/face_geometry.dart';
import 'package:cosmetix/features/virtual_makeup/domain/makeup_look.dart';
import 'package:cosmetix/features/virtual_makeup/engine/blemish_suggester.dart';
import 'package:cosmetix/features/virtual_makeup/engine/color_math.dart';
import 'package:cosmetix/features/virtual_makeup/engine/color_transfer_backend.dart';
import 'package:cosmetix/features/virtual_makeup/engine/makeup_backend.dart';
import 'package:cosmetix/features/virtual_makeup/engine/polygon_raster.dart';
import 'package:cosmetix/features/virtual_makeup/engine/protection_mask.dart';
import 'package:cosmetix/features/virtual_makeup/engine/rgba_image.dart';
import 'package:cosmetix/features/virtual_makeup/landmarks/mediapipe_landmark_provider.dart';
import 'package:cosmetix/features/virtual_makeup/ui/photo_io.dart';
import 'package:cosmetix/features/virtual_makeup/ui/virtual_makeup_controller.dart';

/// REAL MediaPipe on a REAL photo, on a simulator or a phone. The photo is not
/// kept in the repository (it shows a real person): pass the path with
///
///   flutter test integration_test/virtual_makeup_mediapipe_test.dart -d DEVICE \
///     --dart-define=VM_PHOTO=/path/to/face.jpg (optional: --dart-define=VM_OUT=/path/to/dir)
///
/// Without VM_PHOTO the test is skipped. The numbers it prints are for THAT
/// device and THAT build mode; a debug build on a simulator says nothing about
/// release speed on a phone.
const _photo = String.fromEnvironment('VM_PHOTO');
const _out = String.fromEnvironment('VM_OUT');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real face mesh, zones and the no-smoothing contract on a real photo', (
    t,
  ) async {
    if (_photo.isEmpty) {
      markTestSkipped('VM_PHOTO is not set');
      return;
    }
    final bytes = File(_photo).readAsBytesSync();
    final image = await PhotoDecoder.decode(bytes);
    debugPrint('VM_METRIC photo ${image.width}x${image.height}');

    final provider = MediaPipeLandmarkProvider();
    final times = <int>[];
    var faces = await provider.detect(image);
    for (var i = 0; i < 6; i++) {
      final sw = Stopwatch()..start();
      faces = await provider.detect(image);
      sw.stop();
      times.add(sw.elapsedMicroseconds);
    }
    times.sort();
    debugPrint(
      'VM_METRIC detect median(6) ${times[3] / 1000} ms, '
      'max ${times.last / 1000} ms (${kDebugMode
          ? 'DEBUG'
          : kProfileMode
          ? 'PROFILE'
          : 'RELEASE'} build)',
    );
    expect(faces.length, 1);
    expect(faces.first.points.length, FaceIndices.meshSize);

    final face = PreparedFace.from(image, faces.first);
    expect(face.quality.canRun, isTrue);
    debugPrint(
      'VM_METRIC quality issues: ${face.quality.issues.map((e) => e.name).toList()}',
    );
    final fw = face.points.faceWidth;
    expect(fw / image.width, greaterThan(0.2));

    // zones are where they should be
    final lips = _centroid(face.masks.lips);
    final mouth = (face.points[13] + face.points[14]) / 2;
    expect(
      (lips - mouth).distance / fw,
      lessThan(0.05),
      reason: 'lips mask on the mouth',
    );
    final shadow = _centroid(face.masks.eyeshadow);
    final eyeMid = (face.points[159] + face.points[386]) / 2;
    expect(
      shadow.dy,
      lessThan(eyeMid.dy + 0.05 * fw),
      reason: 'shadow on the lids',
    );
    for (final right in [true, false]) {
      final c = ZoneProbe.cheek(face, right: right);
      expect(
        face.masks.skin.at(c.dx.round(), c.dy.round()),
        greaterThan(0.9),
        reason: 'blush centre on skin',
      );
      expect(face.masks.blush.at(c.dx.round(), c.dy.round()), greaterThan(0.7));
    }
    debugPrint(
      'VM_METRIC zones ok; lips off by ${((lips - mouth).distance / fw * 100).toStringAsFixed(1)}% of face width',
    );

    // the contract on a real photo
    const backend = ColorTransferBackend();
    const look = MakeupLook();
    final rt = <int>[];
    RgbaImage out = image;
    for (var i = 0; i < 5; i++) {
      final sw = Stopwatch()..start();
      out = backend.renderSync(MakeupRequest(face: face, look: look));
      sw.stop();
      rt.add(sw.elapsedMicroseconds);
    }
    rt.sort();
    debugPrint(
      'VM_METRIC render median(5) ${rt[2] / 1000} ms for ${image.width}x${image.height}',
    );

    final off = backend.renderSync(
      MakeupRequest(
        face: face,
        look: const MakeupLook(
          lips: ZoneLook(color: ui.Color(0xFFB03A48), intensity: 0),
          eyeshadow: ZoneLook(color: ui.Color(0xFF8A6A7A), enabled: false),
          blush: ZoneLook(color: ui.Color(0xFFE08A8A), intensity: 0),
        ),
      ),
    );
    expect(
      off.pixels,
      orderedEquals(image.pixels),
      reason: 'intensity 0 = the photo, byte for byte',
    );

    var changed = 0, outside = 0;
    for (var y = 0; y < out.height; y++) {
      for (var x = 0; x < out.width; x++) {
        final o = (y * out.width + x) * 4;
        if (out.pixels[o] != image.pixels[o] ||
            out.pixels[o + 1] != image.pixels[o + 1] ||
            out.pixels[o + 2] != image.pixels[o + 2]) {
          changed++;
          if (face.masks.lips.at(x, y) +
                  face.masks.eyeshadow.at(x, y) +
                  face.masks.blush.at(x, y) <=
              0) {
            outside++;
          }
        }
      }
    }
    expect(outside, 0, reason: 'nothing outside the zones changes');
    expect(changed, greaterThan(1000));
    debugPrint(
      'VM_METRIC changed pixels $changed (${(changed * 100 / (image.width * image.height)).toStringAsFixed(2)}% of the photo)',
    );

    // fine detail of every zone is kept
    List<double> lightness(RgbaImage i) => [
      for (var p = 0; p < i.width * i.height; p++)
        ColorMath.rgbToLab(
          i.pixels[p * 4],
          i.pixels[p * 4 + 1],
          i.pixels[p * 4 + 2],
        ).l,
    ];
    final lb = lightness(image), la = lightness(out);
    double detail(List<double> l, bool Function(int, int) m) {
      var e = 0.0;
      for (var y = 1; y < image.height - 1; y++) {
        for (var x = 1; x < image.width - 1; x++) {
          if (!m(x, y)) continue;
          var s = 0.0;
          for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              s += l[(y + dy) * image.width + x + dx];
            }
          }
          final d = l[y * image.width + x] - s / 9;
          e += d * d;
        }
      }
      return e;
    }

    for (final (name, patch) in [
      ('lips', face.masks.lips),
      ('blush', face.masks.blush),
      ('eyeshadow', face.masks.eyeshadow),
    ]) {
      bool inZone(int x, int y) => patch.at(x, y) > 0.5;
      final b = detail(lb, inZone), a = detail(la, inZone);
      final ratio = b > 0 ? a / b : 1.0;
      debugPrint(
        'VM_METRIC detail kept in $name: ${(ratio * 100).toStringAsFixed(1)}%',
      );
      expect(ratio, inInclusiveRange(0.9, 1.15), reason: name);
    }

    // protection on a real photo
    final prot = ProtectionMask(image.width, image.height);
    final cheek = ZoneProbe.cheek(face, right: true);
    prot.dab(cheek.dx, cheek.dy, fw * 0.05, hardness: 1);
    final guarded = backend.renderSync(
      MakeupRequest(face: face, look: look, protection: prot),
    );
    var protectedPixels = 0;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        if (prot.at(x, y) < 1) continue;
        protectedPixels++;
        final o = (y * image.width + x) * 4;
        expect(
          guarded.pixels.sublist(o, o + 3),
          orderedEquals(image.pixels.sublist(o, o + 3)),
        );
      }
    }
    expect(protectedPixels, greaterThan(100));

    final sug = BlemishSuggester.suggest(image, face.masks, fw);
    debugPrint(
      'VM_METRIC suggestion: regions ${sug.regions}, coverage ${(sug.coverage * 100).toStringAsFixed(2)}%, reliable ${sug.reliable} (a hint only)',
    );

    if (_out.isNotEmpty) {
      Directory(_out).createSync(recursive: true);
      Future<void> save(String name, RgbaImage img) async {
        final i = await PhotoDecoder.toUiImage(img);
        final d = await i.toByteData(format: ui.ImageByteFormat.png);
        File('$_out/$name.png').writeAsBytesSync(d!.buffer.asUint8List());
        i.dispose();
      }

      await save('1_original', image);
      await save('2_result', out);
      await save('3_result_with_protection', guarded);
      // the zones, drawn on the photo
      final overlay = image.copy();
      void tint(MaskPatch patch, List<int> rgb) {
        for (var y = patch.y0; y < patch.y0 + patch.height; y++) {
          for (var x = patch.x0; x < patch.x0 + patch.width; x++) {
            final m = patch.at(x, y);
            if (m <= 0) continue;
            final o = (y * overlay.width + x) * 4;
            for (var c = 0; c < 3; c++) {
              overlay.pixels[o + c] =
                  (overlay.pixels[o + c] * (1 - 0.6 * m) + rgb[c] * 0.6 * m)
                      .round();
            }
          }
        }
      }

      tint(face.masks.lips, [255, 0, 80]);
      tint(face.masks.eyeshadow, [60, 80, 255]);
      tint(face.masks.blush, [255, 140, 0]);
      await save('4_zones', overlay);
      for (final k in [0.3, 1.0]) {
        await save(
          '5_intensity_${(k * 100).round()}',
          backend.renderSync(
            MakeupRequest(
              face: face,
              look: MakeupLook(
                lips: ZoneLook(color: const ui.Color(0xFFB03A48), intensity: k),
                eyeshadow: ZoneLook(
                  color: const ui.Color(0xFF8A6A7A),
                  intensity: k,
                ),
                blush: ZoneLook(
                  color: const ui.Color(0xFFE08A8A),
                  intensity: k,
                ),
              ),
            ),
          ),
        );
      }
      debugPrint('VM_METRIC wrote examples to $_out');
    }
    await provider.dispose();
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets(
    'the controller with real MediaPipe: portrait, protection, refused photos, no leaks',
    (t) async {
      if (_photo.isEmpty) {
        markTestSkipped('VM_PHOTO is not set');
        return;
      }
      final portrait = File(_photo).readAsBytesSync();
      final decoded = await PhotoDecoder.decode(portrait);
      Future<Uint8List> pngBytes(RgbaImage img) async {
        final i = await PhotoDecoder.toUiImage(img);
        final d = await i.toByteData(format: ui.ImageByteFormat.png);
        i.dispose();
        return d!.buffer.asUint8List();
      }

      // a picture without any face: a smooth colour gradient
      final plain = RgbaImage(400, 400, Uint8List(400 * 400 * 4));
      for (var y = 0; y < 400; y++) {
        for (var x = 0; x < 400; x++) {
          final o = (y * 400 + x) * 4;
          plain.pixels[o] = 40 + x ~/ 3;
          plain.pixels[o + 1] = 90 + y ~/ 4;
          plain.pixels[o + 2] = 150;
          plain.pixels[o + 3] = 255;
        }
      }
      // the same portrait twice, side by side: two faces
      final w = decoded.width, h = decoded.height;
      final twice = RgbaImage(w * 2, h, Uint8List(w * 2 * h * 4));
      for (var y = 0; y < h; y++) {
        twice.pixels.setRange(
          y * w * 2 * 4,
          y * w * 2 * 4 + w * 4,
          decoded.pixels,
          y * w * 4,
        );
        twice.pixels.setRange(
          y * w * 2 * 4 + w * 4,
          (y + 1) * w * 2 * 4,
          decoded.pixels,
          y * w * 4,
        );
      }
      final plainPng = await pngBytes(plain);
      final twicePng = await pngBytes(twice);

      final provider = MediaPipeLandmarkProvider();
      final c = VirtualMakeupController(landmarks: provider);
      final errors = <Object>[];
      final oldOnError = FlutterError.onError;
      FlutterError.onError = (d) {
        errors.add(d.exception);
        oldOnError?.call(d);
      };

      // 1. the real portrait
      await c.loadPhoto(portrait);
      await t.pump();
      expect(c.status, MakeupStatus.ready);
      expect(c.notice, isNull);
      expect(c.quality!.canRun, isTrue);
      expect(c.face!.points.points.length, FaceIndices.meshSize);
      expect(c.resultImage, isNotNull);
      expect(c.originalImage, isNotNull);
      debugPrint(
        'VM_METRIC controller: portrait ready, ${c.face!.image.width}x${c.face!.image.height}',
      );

      // 2. protection by hand on the cheek, then the result keeps those pixels
      final fw = c.face!.points.faceWidth;
      final cheek = ZoneProbe.cheek(c.face!, right: true);
      c.strokeStart(cheek, fw * 0.04, erase: false);
      for (var i = 1; i <= 25; i++) {
        c.strokeMove(
          cheek + Offset(i * fw * 0.004, i * fw * 0.002),
          fw * 0.04,
          erase: false,
        );
      }
      c.strokeEnd();
      for (var i = 0; i < 40 && c.protectionOverlay == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await t.pump();
      }
      expect(c.protection!.isEmpty, isFalse);
      expect(
        c.protectionOverlay,
        isNotNull,
        reason: 'the protected area is drawn',
      );
      final keptCoverage = c.protection!.coverage;
      final out = const ColorTransferBackend().renderSync(
        MakeupRequest(face: c.face!, look: c.look, protection: c.protection),
      );
      var checked = 0;
      for (var y = 0; y < out.height; y++) {
        for (var x = 0; x < out.width; x++) {
          if (c.protection!.at(x, y) < 1) continue;
          checked++;
          final o = (y * out.width + x) * 4;
          expect(
            out.pixels.sublist(o, o + 3),
            orderedEquals(c.face!.image.pixels.sublist(o, o + 3)),
          );
        }
      }
      expect(checked, greaterThan(100));
      debugPrint(
        'VM_METRIC controller: $checked protected pixels returned byte for byte',
      );

      // 3. refused photos keep the first one (face, result, protection)
      final firstFace = c.face, firstResult = c.resultImage;
      await c.loadPhoto(plainPng);
      await t.pump();
      expect(c.status, MakeupStatus.ready);
      expect(c.notice, MakeupNotice.noFace);
      expect(identical(c.face, firstFace), isTrue);
      expect(identical(c.resultImage, firstResult), isTrue);
      expect(c.protection!.coverage, keptCoverage);

      await c.loadPhoto(twicePng);
      await t.pump();
      expect(c.status, MakeupStatus.ready);
      expect(c.notice, MakeupNotice.severalFaces);
      expect(identical(c.face, firstFace), isTrue);

      await c.loadPhoto(Uint8List.fromList([1, 2, 3, 4, 5]));
      await t.pump();
      expect(c.notice, MakeupNotice.failed);
      expect(identical(c.face, firstFace), isTrue);
      debugPrint(
        'VM_METRIC controller: no face / two faces / broken file all kept the first photo',
      );

      // 4. the same portrait again clears the notice
      await c.loadPhoto(portrait);
      await t.pump();
      expect(c.notice, isNull);
      expect(identical(c.face, firstFace), isFalse);

      // 5. many loads in a row: memory must not climb without limit
      int rss() => ProcessInfo.currentRss;
      for (var i = 0; i < 3; i++) {
        await c.loadPhoto(portrait);
        await t.pump();
      }
      final before = rss();
      var peak = before;
      for (var i = 0; i < 12; i++) {
        await c.loadPhoto(portrait);
        await t.pump();
        await t.pump(const Duration(milliseconds: 20));
        c.strokeStart(const Offset(300, 300), 10, erase: false);
        c.strokeMove(const Offset(340, 330), 10, erase: false);
        c.strokeEnd();
        if (rss() > peak) peak = rss();
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await t.pump();
      final after = rss();
      debugPrint(
        'VM_METRIC memory over 12 loads: before ${(before / 1048576).toStringAsFixed(0)} MB, '
        'after ${(after / 1048576).toStringAsFixed(0)} MB, peak ${(peak / 1048576).toStringAsFixed(0)} MB '
        '(${kDebugMode ? 'DEBUG' : 'RELEASE'} build, simulator: an indication, not a device measurement)',
      );
      expect(
        after - before,
        lessThan(150 * 1048576),
        reason: 'no runaway growth',
      );

      // 6. closing the screen frees what it owns, nothing throws afterwards
      c.dispose();
      await t.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await t.pump();
      FlutterError.onError = oldOnError;
      expect(errors, isEmpty, reason: 'no framework errors during the run');
      expect(t.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

/// The centre of mass of a mask patch, in photo pixels.
Offset _centroid(MaskPatch patch) {
  var sx = 0.0, sy = 0.0, s = 0.0;
  for (var y = 0; y < patch.height; y++) {
    for (var x = 0; x < patch.width; x++) {
      final m = patch.data[y * patch.width + x];
      sx += m * (patch.x0 + x + 0.5);
      sy += m * (patch.y0 + y + 0.5);
      s += m;
    }
  }
  return s > 0 ? Offset(sx / s, sy / s) : Offset.zero;
}

class ZoneProbe {
  /// The cheek centre as the zone builder computes it.
  static Offset cheek(PreparedFace face, {required bool right}) {
    final f = face.points;
    final eye = f[right ? FaceIndices.eyeOuterRight : FaceIndices.eyeOuterLeft];
    final mouth =
        f[right ? FaceIndices.mouthCornerRight : FaceIndices.mouthCornerLeft];
    final ear = f[right ? FaceIndices.faceEdgeRight : FaceIndices.faceEdgeLeft];
    return Offset.lerp(Offset.lerp(eye, mouth, 0.5)!, ear, 0.15)!;
  }
}
