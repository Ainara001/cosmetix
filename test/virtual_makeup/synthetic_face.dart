import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:cosmetix/features/virtual_makeup/domain/face_geometry.dart';
import 'package:cosmetix/features/virtual_makeup/engine/rgba_image.dart';

/// A made-up face for tests: no real person, no photo. The face mesh has the
/// 478 points of MediaPipe but only the indices the module uses are placed; the
/// picture is a flat skin colour with deterministic noise, lips, eyes and brows,
/// and skin "features" the engine must never remove: red dots (acne), a pale
/// line (scar) and a broad red patch (redness).
class SyntheticFace {
  SyntheticFace._(this.image, this.points, this.dots, this.scar, this.patch);

  final RgbaImage image;
  final FacePoints points;

  /// Centres of the red dots (radius [dotRadius]).
  final List<Offset> dots;
  static const dotRadius = 3.0;

  /// The pale line (start, end) and the broad red patch (centre, radius).
  final (Offset, Offset) scar;
  final (Offset, double) patch;

  static const width = 480;
  static const height = 600;

  static SyntheticFace build({
    int seed = 7,
    bool withBlemishes = true,
    double noise = 5,
  }) {
    final pts = List<Offset>.filled(
      FaceIndices.meshSize,
      const Offset(240, 300),
    );
    void place(List<int> ids, List<Offset> at) {
      for (var i = 0; i < ids.length; i++) {
        pts[ids[i]] = at[i];
      }
    }

    // face oval: an ellipse, then the two cheek edges exactly at 90 and 390
    final oval = FaceIndices.faceOval;
    place(oval, [
      for (var k = 0; k < oval.length; k++)
        Offset(
          240 + 150 * math.cos(-math.pi / 2 + 2 * math.pi * k / oval.length),
          300 + 210 * math.sin(-math.pi / 2 + 2 * math.pi * k / oval.length),
        ),
    ]);
    pts[FaceIndices.faceEdgeRight] = const Offset(90, 300);
    pts[FaceIndices.faceEdgeLeft] = const Offset(390, 300);
    pts[FaceIndices.noseTip] = const Offset(240, 345);

    // an eye: lower arc, then the upper arc, outer to inner corner
    void eye(List<int> contour, double cx, double cy, bool outerLeft) {
      final lower = contour.sublist(0, 9), upper = contour.sublist(9);
      final dir = outerLeft ? 1.0 : -1.0;
      final ox = cx - dir * 30;
      place(lower, [
        for (var i = 0; i < 9; i++)
          Offset(ox + dir * 60 * i / 8, cy + 8 * math.sin(math.pi * i / 8)),
      ]);
      place(upper, [
        for (var i = 0; i < 7; i++)
          Offset(
            ox + dir * 60 * (i + 1) / 8,
            cy - 12 * math.sin(math.pi * (i + 1) / 8),
          ),
      ]);
    }

    eye(FaceIndices.eyeRight, 175, 250, true);
    eye(FaceIndices.eyeLeft, 305, 250, false);
    // the lash lines are the upper points plus both corners
    place(FaceIndices.lashRight, [
      pts[33],
      pts[246],
      pts[161],
      pts[160],
      pts[159],
      pts[158],
      pts[157],
      pts[173],
      pts[133],
    ]);
    place(FaceIndices.lashLeft, [
      pts[263],
      pts[466],
      pts[388],
      pts[387],
      pts[386],
      pts[385],
      pts[384],
      pts[398],
      pts[362],
    ]);

    // brows: lower edge outer to inner, upper edge inner to outer
    void brow(List<int> ring, double cx, bool outerLeft) {
      final dir = outerLeft ? 1.0 : -1.0;
      final ox = cx - dir * 35;
      place(ring.sublist(0, 5), [
        for (var i = 0; i < 5; i++)
          Offset(ox + dir * 70 * i / 4, 222 - 3 * math.sin(math.pi * i / 4)),
      ]);
      place(ring.sublist(5), [
        for (var i = 0; i < 5; i++)
          Offset(
            ox + dir * 70 * (4 - i) / 4,
            206 - 4 * math.sin(math.pi * (4 - i) / 4),
          ),
      ]);
    }

    brow(FaceIndices.browRingRight, 175, true);
    brow(FaceIndices.browRingLeft, 305, false);

    // lips: two rings of 20 points, left corner round the bottom to the right
    // corner and back over the top
    void ring(List<int> ids, double rx, double ry) {
      final at = <Offset>[];
      for (var i = 0; i < 20; i++) {
        final t = i < 10 ? i / 10 : (i - 10) / 10;
        final th = i < 10 ? math.pi - t * math.pi : -t * math.pi;
        at.add(Offset(240 + rx * math.cos(th), 430 + ry * math.sin(th)));
      }
      place(ids, at);
    }

    ring(FaceIndices.lipsOuter, 52, 24);
    ring(FaceIndices.lipsInner, 42, 7);

    final face = FacePoints(pts);
    final px = _paint(face, seed, withBlemishes, noise);
    return SyntheticFace._(
      RgbaImage(width, height, Uint8List.fromList(px.pixels)),
      face,
      px.dots,
      px.scar,
      px.patch,
    );
  }

  static ({
    List<int> pixels,
    List<Offset> dots,
    (Offset, Offset) scar,
    (Offset, double) patch,
  })
  _paint(FacePoints face, int seed, bool blemishes, double noise) {
    final rnd = math.Random(seed);
    final data = List<int>.filled(width * height * 4, 0);
    bool inside(List<Offset> poly, double x, double y) {
      var c = false;
      for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
        if ((poly[i].dy > y) != (poly[j].dy > y) &&
            x <
                (poly[j].dx - poly[i].dx) *
                        (y - poly[i].dy) /
                        (poly[j].dy - poly[i].dy) +
                    poly[i].dx) {
          c = !c;
        }
      }
      return c;
    }

    final oval = face.pick(FaceIndices.faceOval);
    final lipsO = face.pick(FaceIndices.lipsOuter),
        lipsI = face.pick(FaceIndices.lipsInner);
    final eyeR = face.pick(FaceIndices.eyeRight),
        eyeL = face.pick(FaceIndices.eyeLeft);
    final browR = face.pick(FaceIndices.browRingRight),
        browL = face.pick(FaceIndices.browRingLeft);
    final dots = blemishes
        ? [
            const Offset(160, 340),
            const Offset(185, 372),
            const Offset(150, 395),
            const Offset(320, 345),
            const Offset(300, 380),
            const Offset(335, 392),
          ]
        : <Offset>[];
    const scar = (Offset(220, 150), Offset(262, 168));
    const patch = (Offset(335, 330), 28.0);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        var r = 228.0, g = 178.0, b = 150.0; // skin
        final px = x + 0.5, py = y + 0.5;
        if (!inside(oval, px, py)) {
          r = 70;
          g = 90;
          b = 120; // background
        } else if (inside(lipsO, px, py) && !inside(lipsI, px, py)) {
          r = 184;
          g = 98;
          b = 108; // lips
        } else if (inside(lipsI, px, py)) {
          r = 60;
          g = 30;
          b = 35; // mouth
        } else if (inside(eyeR, px, py) || inside(eyeL, px, py)) {
          r = 245;
          g = 245;
          b = 245; // eye
        } else if (inside(browR, px, py) || inside(browL, px, py)) {
          r = 80;
          g = 55;
          b = 45; // brow
        } else if (blemishes) {
          for (final d in dots) {
            if ((Offset(px, py) - d).distance <= dotRadius) {
              r = 205;
              g = 105;
              b = 98; // acne
            }
          }
          // scar: a pale line two pixels wide
          final a = scar.$1, c = scar.$2;
          final t =
              (((px - a.dx) * (c.dx - a.dx) + (py - a.dy) * (c.dy - a.dy)) /
                      ((c.dx - a.dx) * (c.dx - a.dx) +
                          (c.dy - a.dy) * (c.dy - a.dy)))
                  .clamp(0.0, 1.0);
          final q = Offset(a.dx + t * (c.dx - a.dx), a.dy + t * (c.dy - a.dy));
          if ((Offset(px, py) - q).distance < 1.2) {
            r = 242;
            g = 205;
            b = 190;
          }
          // redness: a soft patch
          final dd = (Offset(px, py) - patch.$1).distance / patch.$2;
          if (dd < 1) {
            final k = 1 - dd;
            r += 14 * k;
            g -= 30 * k;
            b -= 22 * k;
          }
        }
        // deterministic texture, the same everywhere
        final n = (rnd.nextDouble() - 0.5) * 2 * noise;
        final o = (y * width + x) * 4;
        data[o] = (r + n).round().clamp(0, 255);
        data[o + 1] = (g + n).round().clamp(0, 255);
        data[o + 2] = (b + n).round().clamp(0, 255);
        data[o + 3] = 255;
      }
    }
    return (pixels: data, dots: dots, scar: scar, patch: patch);
  }
}
