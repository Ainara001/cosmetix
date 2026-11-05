import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:cosmetix/database/catalog_data.dart';
import 'package:cosmetix/features/virtual_makeup/domain/face_geometry.dart';
import 'package:cosmetix/features/virtual_makeup/domain/makeup_look.dart';
import 'package:cosmetix/features/virtual_makeup/engine/color_math.dart';
import 'package:cosmetix/features/virtual_makeup/engine/color_transfer_backend.dart';
import 'package:cosmetix/features/virtual_makeup/engine/makeup_backend.dart';
import 'package:cosmetix/features/virtual_makeup/engine/polygon_raster.dart';
import 'package:cosmetix/features/virtual_makeup/engine/protection_mask.dart';
import 'package:cosmetix/features/virtual_makeup/engine/rgba_image.dart';
import 'package:cosmetix/features/virtual_makeup/landmarks/mediapipe_landmark_provider.dart';
import 'package:cosmetix/features/virtual_makeup/ui/photo_io.dart';

/// Quality evaluation of the try-on on a folder of photos, with the REAL face
/// mesh. It measures; it does not claim accuracy: there are no ground-truth
/// zone labels, so no IoU or Dice is computed. Every number is about THESE
/// photos and THIS build (a debug build on a simulator).
///
///   flutter test integration_test/virtual_makeup_eval_test.dart -d DEVICE \
///     --dart-define=EVAL_DIR=/path/to/photos --dart-define=EVAL_OUT=/path/to/out
const _dir = String.fromEnvironment('EVAL_DIR');
const _out = String.fromEnvironment('EVAL_OUT');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('evaluation of zones, shades, protection and speed on photos', (
    t,
  ) async {
    if (_dir.isEmpty || _out.isEmpty) {
      markTestSkipped('EVAL_DIR / EVAL_OUT are not set');
      return;
    }
    Directory(_out).createSync(recursive: true);
    final files =
        Directory(_dir)
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.jpg'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    final licences = <String, String>{};
    final manifest = File('$_dir/../../photos_manifest.json');
    if (manifest.existsSync()) {
      for (final e in jsonDecode(manifest.readAsStringSync()) as List) {
        licences[e['file'] as String] = e['license'] as String;
      }
    }

    // real catalog colours (estimates, see the audit) for the products worn
    final catalog = await CatalogData.load();
    int colourOf(String name) =>
        catalog.products.firstWhere((p) => p.name == name).tryOn!.colour!;
    final berry = ui.Color(colourOf('Ink Mood Glowy Tint 30 Happy Berry'));
    final rose = ui.Color(colourOf('Ink Mood Glowy Tint 03 Rose In Mind'));
    final cheek = ui.Color(colourOf('Better Than Cheek'));
    const shadowColour = ui.Color(0xFF8A6A7A); // hand-picked: no catalog colour

    MakeupLook look({
      ui.Color? lips,
      ui.Color? blush,
      ui.Color? shadow,
      double k = 1,
    }) => MakeupLook(
      lips: ZoneLook(color: lips ?? berry, intensity: k, enabled: lips != null),
      eyeshadow: ZoneLook(
        color: shadow ?? shadowColour,
        intensity: k,
        enabled: shadow != null,
      ),
      blush: ZoneLook(
        color: blush ?? cheek,
        intensity: k,
        enabled: blush != null,
      ),
    );

    final provider = MediaPipeLandmarkProvider();
    const backend = ColorTransferBackend();
    final rows = <Map<String, Object?>>[];

    for (final f in files) {
      final name = f.uri.pathSegments.last;
      final row = <String, Object?>{'file': name, 'licence': licences[name]};
      rows.add(row);
      final image = await PhotoDecoder.decode(f.readAsBytesSync());
      row['size'] = '${image.width}x${image.height}';
      final sw = Stopwatch()..start();
      final faces = await provider.detect(image);
      row['t_detect_ms'] = sw.elapsedMicroseconds / 1000;
      row['faces'] = faces.length;
      if (faces.length != 1) continue;

      sw
        ..reset()
        ..start();
      final face = PreparedFace.from(image, faces.first);
      row['t_prepare_ms'] = sw.elapsedMicroseconds / 1000;
      final fw = face.points.faceWidth;
      row['issues'] = face.quality.issues.map((e) => e.name).join('+');
      row['face_w_px'] = fw.round();
      row['yaw_ratio'] = face.points.yawRatio;
      row['roll_deg'] = face.points.rollDegrees;
      final mouthOpen = (face.points[14] - face.points[13]).distance / fw;
      row['mouth_open_pct_fw'] = mouthOpen * 100;

      // skin lightness: weighted mean L* of the visible skin (no eyes/lips/brows)
      double meanL(MaskPatch m, RgbaImage img, {double minW = 0.5}) {
        var w = 0.0, l = 0.0;
        for (var y = 0; y < m.height; y++) {
          for (var x = 0; x < m.width; x++) {
            final k = m.data[y * m.width + x];
            if (k < minW) continue;
            final o = ((m.y0 + y) * img.width + m.x0 + x) * 4;
            l += ColorMath.rgbToLab(
              img.pixels[o],
              img.pixels[o + 1],
              img.pixels[o + 2],
            ).l;
            w++;
          }
        }
        return w == 0 ? double.nan : l / w;
      }

      final skinL = meanL(face.masks.skin, image);
      row['skin_L'] = skinL;
      row['tone_group'] = skinL >= 65
          ? 'light'
          : (skinL >= 50 ? 'medium' : 'dark');

      double area(MaskPatch m) => m.sum / (fw * fw) * 100;
      row['lips_area_pct_fw2'] = area(face.masks.lips);
      row['shadow_area_pct_fw2'] = area(face.masks.eyeshadow);
      row['blush_area_pct_fw2'] = area(face.masks.blush);

      // ---- everything on at once, 100 %: leaks outside the zones
      final all = look(lips: berry, shadow: shadowColour, blush: cheek);
      sw
        ..reset()
        ..start();
      final first = backend.renderSync(MakeupRequest(face: face, look: all));
      row['t_render_first_ms'] = sw.elapsedMicroseconds / 1000;
      sw
        ..reset()
        ..start();
      final out = backend.renderSync(MakeupRequest(face: face, look: all));
      row['t_render_cached_ms'] = sw.elapsedMicroseconds / 1000;
      sw
        ..reset()
        ..start();
      backend.renderSync(
        MakeupRequest(
          face: face,
          look: look(lips: rose, shadow: shadowColour, blush: cheek),
        ),
      );
      row['t_switch_shade_ms'] = sw.elapsedMicroseconds / 1000;
      expect(first.pixels, orderedEquals(out.pixels), reason: 'repeatable');

      bool changed(int i) =>
          out.pixels[i] != image.pixels[i] ||
          out.pixels[i + 1] != image.pixels[i + 1] ||
          out.pixels[i + 2] != image.pixels[i + 2];
      var outside = 0, total = 0;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final i = (y * image.width + x) * 4;
          if (!changed(i)) continue;
          total++;
          if (face.masks.lips.at(x, y) +
                  face.masks.eyeshadow.at(x, y) +
                  face.masks.blush.at(x, y) <=
              0) {
            outside++;
          }
        }
      }
      row['changed_px'] = total;
      row['changed_outside_zones_px'] = outside;

      // interior of a polygon (eroded by the fill's own soft edge: > 0.9)
      MaskPatch interior(List<int> idx) {
        final pts = face.points.pick(idx);
        final b = PolygonRaster.boundsOf(pts, image.width, image.height)!;
        return PolygonRaster.fill(pts, b.x0, b.y0, b.w, b.h);
      }

      // the CORE of a polygon: pixels that are inside by at least [r] pixels in
      // every direction (a closed mouth has no core: it is a thin line, and a
      // soft mask edge would otherwise count as a leak)
      final r = math.max(3, (fw * 0.006).round());
      MaskPatch core(MaskPatch poly) {
        final c = MaskPatch(poly.x0, poly.y0, poly.width, poly.height);
        for (var y = 0; y < poly.height; y++) {
          for (var x = 0; x < poly.width; x++) {
            var ok = true;
            for (var dy = -r; dy <= r && ok; dy += r) {
              for (var dx = -r; dx <= r && ok; dx += r) {
                if (poly.at(poly.x0 + x + dx, poly.y0 + y + dy) < 0.5) {
                  ok = false;
                }
              }
            }
            if (ok) c.data[y * poly.width + x] = 1;
          }
        }
        return c;
      }

      double coreChanged(List<MaskPatch> polys) {
        var n = 0, c = 0;
        for (final poly in polys) {
          final k = core(poly);
          for (var y = 0; y < k.height; y++) {
            for (var x = 0; x < k.width; x++) {
              if (k.data[y * k.width + x] < 0.5) continue;
              n++;
              final i = ((k.y0 + y) * image.width + k.x0 + x) * 4;
              if (changed(i)) c++;
            }
          }
        }
        return n == 0
            ? -1
            : c * 100 / n; // -1: no core (closed mouth, narrow eye)
      }

      // share of a zone's paint (mask weight) that lies inside a polygon
      double weightIn(MaskPatch zone, List<MaskPatch> polys) {
        var inside = 0.0;
        for (var y = 0; y < zone.height; y++) {
          for (var x = 0; x < zone.width; x++) {
            final k = zone.data[y * zone.width + x];
            if (k <= 0) continue;
            final px = zone.x0 + x, py = zone.y0 + y;
            if (polys.any((p) => p.at(px, py) > 0.5)) inside += k;
          }
        }
        return zone.sum == 0 ? 0 : inside * 100 / zone.sum;
      }

      final eyes = [
        interior(FaceIndices.eyeRight),
        interior(FaceIndices.eyeLeft),
      ];
      final mouth = [interior(FaceIndices.lipsInner)];
      row['eye_core_changed_pct'] = coreChanged(eyes);
      row['mouth_core_changed_pct'] = coreChanged(mouth);
      row['shadow_paint_in_eye_pct'] = weightIn(face.masks.eyeshadow, eyes);
      row['lips_paint_in_mouth_pct'] = weightIn(face.masks.lips, mouth);

      // eyeshadow weight that lies on the eyebrow rings / on very dark pixels
      var shW = 0.0, onBrow = 0.0, onDark = 0.0;
      final brows = [
        interior(FaceIndices.browRingRight),
        interior(FaceIndices.browRingLeft),
      ];
      final sh = face.masks.eyeshadow;
      for (var y = 0; y < sh.height; y++) {
        for (var x = 0; x < sh.width; x++) {
          final k = sh.data[y * sh.width + x];
          if (k <= 0) continue;
          shW += k;
          final px = sh.x0 + x, py = sh.y0 + y;
          if (brows.any((b) => b.at(px, py) > 0.5)) onBrow += k;
          final i = (py * image.width + px) * 4;
          if (ColorMath.rgbToLab(
                image.pixels[i],
                image.pixels[i + 1],
                image.pixels[i + 2],
              ).l <
              20) {
            onDark += k;
          }
        }
      }
      row['shadow_on_brow_pct'] = shW == 0 ? 0 : onBrow * 100 / shW;
      row['shadow_on_dark_px_pct'] = shW == 0 ? 0 : onDark * 100 / shW;

      // lips mask pixels that look like teeth (bright and nearly colourless)
      var lipsN = 0, teeth = 0;
      final lm = face.masks.lips;
      for (var y = 0; y < lm.height; y++) {
        for (var x = 0; x < lm.width; x++) {
          if (lm.data[y * lm.width + x] < 0.5) continue;
          lipsN++;
          final i = ((lm.y0 + y) * image.width + lm.x0 + x) * 4;
          final c = ColorMath.rgbToLab(
            image.pixels[i],
            image.pixels[i + 1],
            image.pixels[i + 2],
          );
          if (c.l > 70 && math.sqrt(c.a * c.a + c.b * c.b) < 18) teeth++;
        }
      }
      row['lips_teeth_like_pct'] = lipsN == 0 ? 0 : teeth * 100 / lipsN;

      // ---- colour: how far the mean colour of a zone gets to the product's
      Lab zoneMean(MaskPatch m, RgbaImage img, double minW) {
        var w = 0.0, l = 0.0, a = 0.0, b = 0.0;
        for (var y = 0; y < m.height; y++) {
          for (var x = 0; x < m.width; x++) {
            final k = m.data[y * m.width + x];
            if (k < minW) continue;
            final o = ((m.y0 + y) * img.width + m.x0 + x) * 4;
            final c = ColorMath.rgbToLab(
              img.pixels[o],
              img.pixels[o + 1],
              img.pixels[o + 2],
            );
            w++;
            l += c.l;
            a += c.a;
            b += c.b;
          }
        }
        return w == 0 ? const Lab(0, 0, 0) : Lab(l / w, a / w, b / w);
      }

      void shade(String tag, ui.Color colour, MakeupZone zone, MaskPatch m) {
        final before = zoneMean(m, image, 0.9);
        final target = ColorMath.colorToLab(colour);
        for (final k in [0.6, 1.0]) {
          final img = backend.renderSync(
            MakeupRequest(
              face: face,
              look: look(
                lips: zone == MakeupZone.lips ? colour : null,
                blush: zone == MakeupZone.blush ? colour : null,
                shadow: zone == MakeupZone.eyeshadow ? colour : null,
                k: k,
              ),
            ),
          );
          final after = zoneMean(m, img, 0.9);
          final p = '${tag}_${(k * 100).round()}';
          row['${p}_dE00_to_product'] = ColorMath.deltaE2000(after, target);
          row['${p}_dE00_change'] = ColorMath.deltaE2000(before, after);
          row['${p}_dL'] = after.l - before.l;
        }
        row['${tag}_dE00_start_to_product'] = ColorMath.deltaE2000(
          before,
          target,
        );
      }

      shade('lips_berry', berry, MakeupZone.lips, face.masks.lips);
      shade('lips_rose', rose, MakeupZone.lips, face.masks.lips);
      shade('blush_cheek', cheek, MakeupZone.blush, face.masks.blush);
      shade(
        'shadow_hand',
        shadowColour,
        MakeupZone.eyeshadow,
        face.masks.eyeshadow,
      );

      // ---- protection with several products worn together
      final prot = ProtectionMask(image.width, image.height);
      final c0 = face.masks.blush;
      // the centre of the blush patch (a cheek) and the middle of the lips
      prot.dab(
        c0.x0 + c0.width * 0.25,
        c0.y0 + c0.height / 2,
        fw * 0.04,
        hardness: 1,
      );
      final lm0 = face.masks.lips;
      prot.dab(
        lm0.x0 + lm0.width / 2,
        lm0.y0 + lm0.height / 2,
        fw * 0.03,
        hardness: 1,
      );
      final guarded = backend.renderSync(
        MakeupRequest(face: face, look: all, protection: prot),
      );
      var pn = 0, pBad = 0;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          if (prot.at(x, y) < 1) continue;
          pn++;
          final i = (y * image.width + x) * 4;
          if (guarded.pixels[i] != image.pixels[i] ||
              guarded.pixels[i + 1] != image.pixels[i + 1] ||
              guarded.pixels[i + 2] != image.pixels[i + 2]) {
            pBad++;
          }
        }
      }
      row['protected_px'] = pn;
      row['protected_changed_px'] = pBad;

      // ---- texture: the detail (pixel minus 3x3 mean) of a zone is kept
      double detail(RgbaImage img, MaskPatch m) {
        double lum(int x, int y) {
          final o = (y * img.width + x) * 4;
          return ColorMath.rgbToLab(
            img.pixels[o],
            img.pixels[o + 1],
            img.pixels[o + 2],
          ).l;
        }

        var e = 0.0;
        for (var y = 1; y < m.height - 1; y++) {
          for (var x = 1; x < m.width - 1; x++) {
            if (m.data[y * m.width + x] < 0.5) continue;
            final px = m.x0 + x, py = m.y0 + y;
            var s = 0.0;
            for (var dy = -1; dy <= 1; dy++) {
              for (var dx = -1; dx <= 1; dx++) {
                s += lum(px + dx, py + dy);
              }
            }
            final d = lum(px, py) - s / 9;
            e += d * d;
          }
        }
        return e;
      }

      for (final (tag, m) in [
        ('lips', face.masks.lips),
        ('blush', face.masks.blush),
        ('shadow', face.masks.eyeshadow),
      ]) {
        final b = detail(image, m);
        row['detail_${tag}_pct'] = b > 0 ? detail(out, m) / b * 100 : null;
      }

      // ---- pictures to look at: before, after, zones
      Future<void> save(String suffix, RgbaImage img) async {
        final u = await PhotoDecoder.toUiImage(img);
        final d = await u.toByteData(format: ui.ImageByteFormat.png);
        File(
          '$_out/${name.replaceAll('.jpg', '')}_$suffix.png',
        ).writeAsBytesSync(d!.buffer.asUint8List());
        u.dispose();
      }

      await save('1_before', image);
      await save('2_after', out);
      final overlay = image.copy();
      void tint(MaskPatch patch, List<int> rgb) {
        for (var y = 0; y < patch.height; y++) {
          for (var x = 0; x < patch.width; x++) {
            final m = patch.data[y * patch.width + x];
            if (m <= 0) continue;
            final o = ((patch.y0 + y) * overlay.width + patch.x0 + x) * 4;
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
      await save('3_zones', overlay);
      await save('4_protected', guarded);
    }

    // results as JSON (one object per photo)
    File(
      '$_out/results.json',
    ).writeAsStringSync(const JsonEncoder.withIndent(' ').convert(rows));
    debugPrint(
      'EVAL_DONE photos=${rows.length} out=$_out '
      '${kDebugMode ? 'DEBUG' : 'RELEASE'} rss_mb=${(ProcessInfo.currentRss / 1048576).round()}',
    );
    await provider.dispose();
  }, timeout: const Timeout(Duration(minutes: 20)));
}
