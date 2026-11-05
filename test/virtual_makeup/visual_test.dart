import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:cosmetix/features/virtual_makeup/domain/makeup_look.dart';
import 'package:cosmetix/features/virtual_makeup/engine/color_transfer_backend.dart';
import 'package:cosmetix/features/virtual_makeup/engine/makeup_backend.dart';
import 'package:cosmetix/features/virtual_makeup/engine/protection_mask.dart';
import 'package:cosmetix/features/virtual_makeup/engine/rgba_image.dart';
import 'package:cosmetix/features/virtual_makeup/ui/photo_io.dart';

import 'synthetic_face.dart';

const _backend = ColorTransferBackend();

/// Box-average downscale by an integer [k]: a small picture that is stable to
/// compare and small enough to keep in the repository.
RgbaImage downscale(RgbaImage src, int k) {
  final w = src.width ~/ k, h = src.height ~/ k;
  final out = RgbaImage.blank(w, h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      for (var c = 0; c < 3; c++) {
        var s = 0;
        for (var dy = 0; dy < k; dy++) {
          for (var dx = 0; dx < k; dx++) {
            s += src.pixels[((y * k + dy) * src.width + x * k + dx) * 4 + c];
          }
        }
        out.pixels[(y * w + x) * 4 + c] = (s / (k * k)).round();
      }
      out.pixels[(y * w + x) * 4 + 3] = 255;
    }
  }
  return out;
}

RgbaImage sideBySide(List<RgbaImage> images) {
  final h = images.first.height;
  final w = images.fold<int>(0, (s, i) => s + i.width);
  final out = RgbaImage.blank(w, h);
  var x0 = 0;
  for (final img in images) {
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < img.width; x++) {
        final so = (y * img.width + x) * 4, d = (y * w + x0 + x) * 4;
        out.pixels.setRange(d, d + 4, img.pixels.sublist(so, so + 4));
      }
    }
    x0 += img.width;
  }
  return out;
}

Future<Uint8List> png(RgbaImage img) async {
  final i = await PhotoDecoder.toUiImage(img);
  final d = await i.toByteData(format: ui.ImageByteFormat.png);
  i.dispose();
  return d!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final f = SyntheticFace.build();
  final face = PreparedFace.from(f.image, f.points);

  RgbaImage render(MakeupLook look, {ProtectionMask? protection}) =>
      _backend.renderSync(
        MakeupRequest(face: face, look: look, protection: protection),
      );

  test(
    'a zone is tinted only where it should be (visual check by numbers)',
    () {
      for (final z in MakeupZone.values) {
        final only = MakeupLook(
          lips: ZoneLook(
            color: const Color0(0xFFB03A48).c,
            enabled: z == MakeupZone.lips,
          ),
          eyeshadow: ZoneLook(
            color: const Color0(0xFF5B6B8A).c,
            enabled: z == MakeupZone.eyeshadow,
          ),
          blush: ZoneLook(
            color: const Color0(0xFFE08A8A).c,
            enabled: z == MakeupZone.blush,
          ),
        );
        final out = render(only);
        var changed = 0, inside = 0;
        final patch = face.maskOf(z);
        for (var y = 0; y < out.height; y++) {
          for (var x = 0; x < out.width; x++) {
            final o = (y * out.width + x) * 4;
            if (out.pixels[o] == f.image.pixels[o] &&
                out.pixels[o + 1] == f.image.pixels[o + 1] &&
                out.pixels[o + 2] == f.image.pixels[o + 2]) {
              continue;
            }
            changed++;
            if (patch.at(x, y) > 0) inside++;
          }
        }
        expect(changed, greaterThan(500), reason: z.name);
        expect(
          inside,
          changed,
          reason: '${z.name}: nothing outside its own zone',
        );
      }
    },
  );

  test(
    'golden: the default look on the synthetic face (small picture)',
    () async {
      final out = render(const MakeupLook());
      final small = sideBySide([downscale(f.image, 3), downscale(out, 3)]);
      final file = File('test/virtual_makeup/goldens/default_look.png');
      // the picture is written only on purpose (UPDATE_GOLDENS=1); a missing
      // file is a failure, not a reason to make a new "correct" answer
      if (Platform.environment['UPDATE_GOLDENS'] == '1') {
        file.writeAsBytesSync(await png(small));
      }
      expect(
        file.existsSync(),
        isTrue,
        reason: 'run once with UPDATE_GOLDENS=1 and check the picture by eye',
      );
      final stored = await PhotoDecoder.decode(file.readAsBytesSync());
      expect(stored.width, small.width);
      expect(stored.height, small.height);
      var worst = 0;
      for (var i = 0; i < small.pixels.length; i++) {
        if (i % 4 == 3) continue;
        final d = (small.pixels[i] - stored.pixels[i]).abs();
        if (d > worst) worst = d;
      }
      // the same engine on the same input: at most a rounding step apart
      expect(worst, lessThanOrEqualTo(2));
    },
  );

  test(
    'examples for the report (written only when VM_EXAMPLES_DIR is set)',
    () async {
      final dir = Platform.environment['VM_EXAMPLES_DIR'];
      if (dir == null) return;
      Directory(dir).createSync(recursive: true);
      final prot = ProtectionMask(SyntheticFace.width, SyntheticFace.height);
      for (final d in f.dots) {
        prot.dab(d.dx, d.dy, 9, hardness: 1);
      }
      final rows = <String, RgbaImage>{
        'intensity_30_60_100': sideBySide([
          for (final k in [0.3, 0.6, 1.0])
            render(
              MakeupLook(
                lips: ZoneLook(color: const Color0(0xFFB03A48).c, intensity: k),
                eyeshadow: ZoneLook(
                  color: const Color0(0xFF8A6A7A).c,
                  intensity: k,
                ),
                blush: ZoneLook(
                  color: const Color0(0xFFE08A8A).c,
                  intensity: k,
                ),
              ),
            ),
        ]),
        'original_result_protected': sideBySide([
          f.image,
          render(const MakeupLook()),
          render(const MakeupLook(), protection: prot),
        ]),
      };
      for (final e in rows.entries) {
        File('$dir/${e.key}.png').writeAsBytesSync(await png(e.value));
      }
    },
  );
}

/// A const-friendly wrapper so the lines above stay short.
class Color0 {
  const Color0(this.v);
  final int v;
  ui.Color get c => ui.Color(v);
}
