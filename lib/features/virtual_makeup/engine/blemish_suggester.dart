import 'dart:math' as math;
import 'dart:typed_data';

import 'color_math.dart';
import 'polygon_raster.dart';
import 'rgba_image.dart';
import 'zone_masks.dart';

/// A HINT about small spots on the skin, never a diagnosis and never a claim of
/// accuracy. It marks small reddish or dark spots that stand out from the skin
/// around them. It misses things (flat redness, pale scars, spots in shadow)
/// and marks things that are not blemishes (moles, freckles, hair, pores), so
/// the user always checks it and corrects it by hand.
class BlemishSuggestion {
  const BlemishSuggestion({
    required this.mask,
    required this.regions,
    required this.coverage,
    required this.reliable,
  });

  /// Photo-sized, 255 where a spot was suggested, 0 elsewhere.
  final Uint8List mask;
  final int regions;

  /// Share of the visible skin that was marked, 0..1.
  final double coverage;

  /// False when too much was marked (lighting or makeup, not spots): the
  /// suggestion is then empty and the user is told to mark by hand.
  final bool reliable;
}

class BlemishSuggester {
  BlemishSuggester._();

  static const maxCoverage = 0.12;

  static BlemishSuggestion suggest(
    RgbaImage image,
    ZoneMasks masks,
    double faceWidth,
  ) {
    final empty = BlemishSuggestion(
      mask: Uint8List(image.width * image.height),
      regions: 0,
      coverage: 0,
      reliable: true,
    );
    final skin = masks.skin;
    if (skin.isEmpty) return empty;
    // work at a small size: about 320 cells across the face
    final s = math.max(1, (faceWidth / 320).floor());
    final sw = (skin.width / s).ceil(), sh = (skin.height / s).ceil();
    final valid = MaskPatch(0, 0, sw, sh);
    final la = MaskPatch(0, 0, sw, sh);
    final aa = MaskPatch(0, 0, sw, sh);
    for (var cy = 0; cy < sh; cy++) {
      for (var cx = 0; cx < sw; cx++) {
        var r = 0, g = 0, b = 0, n = 0;
        var sk = 0.0;
        for (var dy = 0; dy < s; dy++) {
          final y = skin.y0 + cy * s + dy;
          if (y >= image.height || cy * s + dy >= skin.height) break;
          for (var dx = 0; dx < s; dx++) {
            final x = skin.x0 + cx * s + dx;
            if (x >= image.width || cx * s + dx >= skin.width) break;
            final o = (y * image.width + x) * 4;
            r += image.pixels[o];
            g += image.pixels[o + 1];
            b += image.pixels[o + 2];
            sk += skin.at(x, y);
            n++;
          }
        }
        if (n == 0) continue;
        final i = cy * sw + cx;
        if (sk / n > 0.9) {
          valid.data[i] = 1;
          final lab = ColorMath.rgbToLab(r ~/ n, g ~/ n, b ~/ n);
          la.data[i] = lab.l;
          aa.data[i] = lab.a;
        }
      }
    }
    var validCount = 0;
    for (final v in valid.data) {
      if (v > 0) validCount++;
    }
    if (validCount < 50) return empty;

    // the skin "around": a blur that ignores the cells that are not skin
    final radius = math.max(2.0, 0.045 * faceWidth / s);
    final baseA = _maskedBlur(aa, valid, radius);
    final baseL = _maskedBlur(la, valid, radius);
    final devA = <double>[], devL = <double>[];
    for (var i = 0; i < valid.data.length; i++) {
      if (valid.data[i] > 0) {
        devA.add(aa.data[i] - baseA[i]);
        devL.add(la.data[i] - baseL[i]);
      }
    }
    final thrA = math.max(3.0, _median(devA) + 3.5 * 1.4826 * _mad(devA));
    final thrL = math.max(7.0, 4 * 1.4826 * _mad(devL));
    final cand = Uint8List(sw * sh);
    for (var i = 0; i < cand.length; i++) {
      if (valid.data[i] > 0 &&
          (aa.data[i] - baseA[i] > thrA || la.data[i] - baseL[i] < -thrL)) {
        cand[i] = 1;
      }
    }
    // keep only SMALL spots: big areas are shadows, light or makeup, which a
    // colour test cannot tell from real skin features
    final maxArea = math.max(6, (0.01 * validCount).round());
    final keep = Uint8List(sw * sh);
    var regions = 0;
    final seen = Uint8List(sw * sh);
    final stack = <int>[];
    for (var start = 0; start < cand.length; start++) {
      if (cand[start] == 0 || seen[start] == 1) continue;
      final comp = <int>[];
      stack.add(start);
      seen[start] = 1;
      while (stack.isNotEmpty) {
        final i = stack.removeLast();
        comp.add(i);
        final x = i % sw, y = i ~/ sw;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final nx = x + dx, ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= sw || ny >= sh) continue;
            final j = ny * sw + nx;
            if (cand[j] == 1 && seen[j] == 0) {
              seen[j] = 1;
              stack.add(j);
            }
          }
        }
      }
      if (comp.length >= 3 && comp.length <= maxArea) {
        regions++;
        for (final i in comp) {
          keep[i] = 1;
        }
      }
    }
    // grow by one cell so the whole spot and its rim are covered
    final grown = Uint8List.fromList(keep);
    for (var i = 0; i < keep.length; i++) {
      if (keep[i] == 0) continue;
      final x = i % sw, y = i ~/ sw;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx, ny = y + dy;
          if (nx >= 0 &&
              ny >= 0 &&
              nx < sw &&
              ny < sh &&
              valid.data[ny * sw + nx] > 0) {
            grown[ny * sw + nx] = 1;
          }
        }
      }
    }
    var marked = 0;
    for (final v in grown) {
      marked += v;
    }
    final coverage = marked / validCount;
    if (coverage > maxCoverage) {
      return BlemishSuggestion(
        mask: Uint8List(image.width * image.height),
        regions: 0,
        coverage: coverage,
        reliable: false,
      );
    }
    final mask = Uint8List(image.width * image.height);
    for (var i = 0; i < grown.length; i++) {
      if (grown[i] == 0) continue;
      final cx = i % sw, cy = i ~/ sw;
      for (var dy = 0; dy < s; dy++) {
        final y = skin.y0 + cy * s + dy;
        if (y >= image.height) break;
        for (var dx = 0; dx < s; dx++) {
          final x = skin.x0 + cx * s + dx;
          if (x >= image.width) break;
          mask[y * image.width + x] = 255;
        }
      }
    }
    return BlemishSuggestion(
      mask: mask,
      regions: regions,
      coverage: coverage,
      reliable: true,
    );
  }

  static Float32List _maskedBlur(
    MaskPatch values,
    MaskPatch valid,
    double radius,
  ) {
    final num = MaskPatch(0, 0, values.width, values.height);
    final den = MaskPatch(0, 0, values.width, values.height);
    for (var i = 0; i < num.data.length; i++) {
      num.data[i] = values.data[i] * valid.data[i];
      den.data[i] = valid.data[i];
    }
    PolygonRaster.blur(num, radius);
    PolygonRaster.blur(den, radius);
    final out = Float32List(num.data.length);
    for (var i = 0; i < out.length; i++) {
      out[i] = den.data[i] > 1e-6 ? num.data[i] / den.data[i] : values.data[i];
    }
    return out;
  }

  static double _median(List<double> v) {
    if (v.isEmpty) return 0;
    final s = [...v]..sort();
    return s[s.length ~/ 2];
  }

  static double _mad(List<double> v) {
    final m = _median(v);
    return _median([for (final x in v) (x - m).abs()]);
  }
}
