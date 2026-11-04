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
