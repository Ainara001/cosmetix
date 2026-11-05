import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

/// A float mask (0..1) of a rectangle of the photo.
class MaskPatch {
  MaskPatch(this.x0, this.y0, this.width, this.height)
    : data = Float32List(width * height);

  /// Top-left corner in photo pixels.
  final int x0;
  final int y0;
  final int width;
  final int height;
  final Float32List data;

  /// The mask value at photo pixel ([x], [y]); 0 outside the patch.
  double at(int x, int y) {
    final px = x - x0, py = y - y0;
    if (px < 0 || py < 0 || px >= width || py >= height) return 0;
    return data[py * width + px];
  }

  bool get isEmpty => width <= 0 || height <= 0;

  double get sum {
    var s = 0.0;
    for (final v in data) {
      s += v;
    }
    return s;
  }
}

class PolygonRaster {
  PolygonRaster._();

  /// Anti-aliased fill (4 sub-scanlines per pixel, exact horizontal coverage)
  /// of [polygon] (even-odd) into a patch covering [x0, y0, w, h] of the photo.
  static MaskPatch fill(List<Offset> polygon, int x0, int y0, int w, int h) {
    final patch = MaskPatch(x0, y0, w, h);
    if (polygon.length < 3 || w <= 0 || h <= 0) return patch;
    const sub = 4;
    final xs = <double>[];
    for (var row = 0; row < h; row++) {
      final base = row * w;
      for (var s = 0; s < sub; s++) {
        final sy = y0 + row + (s + 0.5) / sub;
        xs.clear();
        for (var i = 0; i < polygon.length; i++) {
          final p = polygon[i], q = polygon[(i + 1) % polygon.length];
          if ((p.dy <= sy && q.dy > sy) || (q.dy <= sy && p.dy > sy)) {
            xs.add(p.dx + (sy - p.dy) * (q.dx - p.dx) / (q.dy - p.dy));
          }
        }
        if (xs.length < 2) continue;
        xs.sort();
        for (var k = 0; k + 1 < xs.length; k += 2) {
          final xa = xs[k] - x0, xb = xs[k + 1] - x0;
          if (xb <= 0 || xa >= w) continue;
          final from = math.max(0, xa.floor());
          final to = math.min(w - 1, xb.floor());
          for (var px = from; px <= to; px++) {
            final overlap =
                math.min(px + 1.0, xb) - math.max(px.toDouble(), xa);
            if (overlap > 0) patch.data[base + px] += overlap / sub;
          }
        }
      }
    }
    for (var i = 0; i < patch.data.length; i++) {
      if (patch.data[i] > 1) patch.data[i] = 1;
    }
    return patch;
  }

  /// The patch rectangle around [polygon], grown by [margin] pixels and kept
  /// inside a [width] x [height] photo. Null when nothing is left.
  static ({int x0, int y0, int w, int h})? boundsOf(
    List<Offset> polygon,
    int width,
    int height, {
    int margin = 0,
  }) {
    if (polygon.isEmpty) return null;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final p in polygon) {
      minX = math.min(minX, p.dx);
      minY = math.min(minY, p.dy);
      maxX = math.max(maxX, p.dx);
      maxY = math.max(maxY, p.dy);
    }
    final x0 = math.max(0, minX.floor() - margin);
    final y0 = math.max(0, minY.floor() - margin);
    final x1 = math.min(width, maxX.ceil() + 1 + margin);
    final y1 = math.min(height, maxY.ceil() + 1 + margin);
    if (x1 <= x0 || y1 <= y0) return null;
    return (x0: x0, y0: y0, w: x1 - x0, h: y1 - y0);
  }

  /// Blurs a patch in place with three box passes (close to a Gaussian). The
  /// blur is applied to the MASK only, never to the photo.
  static void blur(MaskPatch patch, double radius) {
    final r = radius.round();
    if (r < 1) return;
    final tmp = Float32List(patch.data.length);
    for (var pass = 0; pass < 3; pass++) {
      _boxH(patch.data, tmp, patch.width, patch.height, r);
      _boxV(tmp, patch.data, patch.width, patch.height, r);
    }
  }

  static void _boxH(Float32List src, Float32List dst, int w, int h, int r) {
    final norm = 1.0 / (2 * r + 1);
    for (var y = 0; y < h; y++) {
      final row = y * w;
      var sum = 0.0;
      for (var x = -r; x <= r; x++) {
        sum += src[row + x.clamp(0, w - 1)];
      }
      for (var x = 0; x < w; x++) {
        dst[row + x] = sum * norm;
        sum +=
            src[row + (x + r + 1).clamp(0, w - 1)] -
            src[row + (x - r).clamp(0, w - 1)];
      }
    }
  }

  static void _boxV(Float32List src, Float32List dst, int w, int h, int r) {
    final norm = 1.0 / (2 * r + 1);
    for (var x = 0; x < w; x++) {
      var sum = 0.0;
      for (var y = -r; y <= r; y++) {
        sum += src[y.clamp(0, h - 1) * w + x];
      }
      for (var y = 0; y < h; y++) {
        dst[y * w + x] = sum * norm;
        sum +=
            src[(y + r + 1).clamp(0, h - 1) * w + x] -
            src[(y - r).clamp(0, h - 1) * w + x];
      }
    }
  }
}
