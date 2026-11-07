import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:cosmetix/services/photo_check/photo_check.dart';

import 'mean_mesh.dart';

/// Synthetic faces for the tests of the photo check: no real person, no photo
/// file. A face is the mean mesh placed and scaled in a frame, painted with a
/// skin colour, open eyes (white with a dark iris), red lips, grain and a soft
/// shading, on a grey-blue background.
const _faceOval = [
  10,
  338,
  297,
  332,
  284,
  251,
  389,
  356,
  454,
  323,
  361,
  288,
  397,
  365,
  379,
  378,
  400,
  377,
  152,
  148,
  176,
  149,
  150,
  136,
  172,
  58,
  132,
  93,
  234,
  127,
  162,
  21,
  54,
  103,
  67,
  109,
];
const _lips = [
  61,
  146,
  91,
  181,
  84,
  17,
  314,
  405,
  321,
  375,
  291,
  409,
  270,
  269,
  267,
  0,
  37,
  39,
  40,
  185,
];
const _eyeRight = [
  33,
  7,
  163,
  144,
  145,
  153,
  154,
  155,
  133,
  173,
  157,
  158,
  159,
  160,
  161,
  246,
];
const _eyeLeft = [
  263,
  249,
  390,
  373,
  374,
  380,
  381,
  382,
  362,
  398,
  384,
  385,
  386,
  387,
  388,
  466,
];

/// The mean mesh at [center] with the cheek edges [width] px apart.
/// [nose] moves the nose tip sideways by that fraction of the width (a turned head).
List<Offset> meshAt(Offset center, double width, {double nose = 0}) {
  final pts = [
    for (var i = 0; i < 478; i++)
      Offset(
        center.dx + meanMesh[2 * i] * width,
        center.dy + meanMesh[2 * i + 1] * width,
      ),
  ];
  if (nose != 0) pts[4] = pts[4] + Offset(nose * width, 0);
  return pts;
}

class Canvas8 {
  Canvas8(this.w, this.h, {List<int> background = const [90, 100, 112]})
    : rgba = Uint8List(w * h * 4) {
    for (var i = 0; i < w * h; i++) {
      rgba[i * 4] = background[0];
      rgba[i * 4 + 1] = background[1];
      rgba[i * 4 + 2] = background[2];
      rgba[i * 4 + 3] = 255;
    }
  }

  final int w, h;
  final Uint8List rgba;

  PhotoPixels get pixels => PhotoPixels(w, h, rgba);

  void fill(
    List<Offset> poly,
    List<int> color, {
    double shade = 0,
    double noise = 0,
    math.Random? rnd,
  }) {
    for (var y = 0; y < h; y++) {
      final yc = y + 0.5;
      final xs = <double>[];
      for (var i = 0; i < poly.length; i++) {
        final a = poly[i], b = poly[(i + 1) % poly.length];
        if ((a.dy <= yc && b.dy > yc) || (b.dy <= yc && a.dy > yc)) {
          xs.add(a.dx + (yc - a.dy) * (b.dx - a.dx) / (b.dy - a.dy));
        }
      }
      xs.sort();
      for (var k = 0; k + 1 < xs.length; k += 2) {
        for (
          var x = math.max(0, (xs[k] - 0.5).ceil());
          x <= math.min(w - 1, (xs[k + 1] - 0.5).floor());
          x++
        ) {
          // soft shading from the left (bright) to the right, plus grain
          final g = 1 + shade * (0.5 - x / w);
          final n = noise == 0 ? 0 : (rnd!.nextDouble() - 0.5) * 2 * noise;
          final o = (y * w + x) * 4;
          for (var c = 0; c < 3; c++) {
            rgba[o + c] = (color[c] * g + n).round().clamp(0, 255);
          }
        }
      }
    }
  }

  /// Paints the face of [mesh]: skin, eyes, lips.
  void face(
    List<Offset> mesh,
    List<int> skin, {
    double shade = 0.35,
    double grain = 7,
    int seed = 1,
  }) {
    final rnd = math.Random(seed);
    fill(
      [for (final i in _faceOval) mesh[i]],
      skin,
      shade: shade,
      noise: grain,
      rnd: rnd,
    );
    for (final loop in [_eyeRight, _eyeLeft]) {
      final pts = [for (final i in loop) mesh[i]];
      fill(pts, [235, 232, 228], noise: grain / 2, rnd: rnd);
      final c = Offset(
        pts.map((p) => p.dx).reduce((a, b) => a + b) / pts.length,
        pts.map((p) => p.dy).reduce((a, b) => a + b) / pts.length,
      );
      final r =
          (pts.map((p) => p.dx).reduce(math.max) -
              pts.map((p) => p.dx).reduce(math.min)) *
          0.3;
      fill(
        [
          for (var a = 0; a < 16; a++)
            c +
                Offset(
                  math.cos(a * math.pi / 8) * r,
                  math.sin(a * math.pi / 8) * r,
                ),
        ],
        [45, 32, 26],
      );
    }
    fill(
      [for (final i in _lips) mesh[i]],
      [168, 70, 80],
      noise: grain / 2,
      rnd: rnd,
    );
  }

  /// Dark, flat lenses over both eyes (and the bridge): what sunglasses look like to a rule.
  void lenses(List<Offset> mesh, int gray) {
    for (final loop in [_eyeRight, _eyeLeft]) {
      final pts = [for (final i in loop) mesh[i]];
      final c = Offset(
        pts.map((p) => p.dx).reduce((a, b) => a + b) / pts.length,
        pts.map((p) => p.dy).reduce((a, b) => a + b) / pts.length,
      );
      fill([for (final p in pts) c + (p - c) * 1.9], [gray, gray, gray]);
    }
  }

  /// A box blur of [radius] pixels (a photo out of focus).
  void blur(int radius) {
    for (var pass = 0; pass < 2; pass++) {
      final src = Uint8List.fromList(rgba);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          for (var c = 0; c < 3; c++) {
            var s = 0, n = 0;
            for (var d = -radius; d <= radius; d++) {
              final xx = x + d;
              if (xx < 0 || xx >= w) continue;
              s += src[(y * w + xx) * 4 + c];
              n++;
            }
            rgba[(y * w + x) * 4 + c] = s ~/ n;
          }
        }
      }
      final tmp = Uint8List.fromList(rgba);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          for (var c = 0; c < 3; c++) {
            var s = 0, n = 0;
            for (var d = -radius; d <= radius; d++) {
              final yy = y + d;
              if (yy < 0 || yy >= h) continue;
              s += tmp[(yy * w + x) * 4 + c];
              n++;
            }
            rgba[(y * w + x) * 4 + c] = s ~/ n;
          }
        }
      }
    }
  }

  /// Every channel times [k] (clipped): darker or brighter.
  void gain(double k) {
    for (var i = 0; i < w * h; i++) {
      for (var c = 0; c < 3; c++) {
        rgba[i * 4 + c] = (rgba[i * 4 + c] * k).round().clamp(0, 255);
      }
    }
  }
}

/// A finder that returns what the test says.
class FakeFinder implements PhotoFaceFinder {
  FakeFinder(this.faces, {this.throws = false});

  List<List<Offset>> faces;
  final bool throws;
  int calls = 0;

  @override
  Future<List<List<Offset>>> find(PhotoPixels photo) async {
    calls++;
    if (throws) throw StateError('detector failed');
    return faces;
  }

  @override
  Future<void> dispose() async {}
}

/// Light skin, medium and dark skin as in a well-lit photo (midtones, not black).
const lightSkin = [214, 168, 142];
const mediumSkin = [180, 128, 98];
const darkSkin = [155, 100, 75];
