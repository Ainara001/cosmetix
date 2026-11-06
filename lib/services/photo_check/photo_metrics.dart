import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:cosmetix/services/photo_check/photo_pixels.dart';
import 'package:cosmetix/services/photo_check/photo_rules.dart';

/// Measurements on ONE face of a photo, from its 478 landmarks (pixel
/// coordinates of the photo) and the pixels. Port of `measure()` in
/// `tools/eval/photo_quality.py` (the reference): the same zones, the same
/// definitions, so the numbers can be compared photo by photo.
///
/// Pure Dart, no plugins, no network: nothing here can send a photo anywhere.
class PhotoMeasure {
  PhotoMeasure._();

  // landmark loops (MediaPipe Face Mesh indices); see tools/eval/face_zones.py
  static const _forehead = [
    54,
    103,
    67,
    109,
    10,
    338,
    297,
    332,
    284,
    300,
    293,
    334,
    296,
    336,
    9,
    107,
    66,
    105,
    63,
    70,
    21,
  ];
  static const _nose = [
    193,
    122,
    196,
    174,
    217,
    198,
    209,
    49,
    64,
    98,
    97,
    2,
    326,
    327,
    294,
    279,
    429,
    420,
    437,
    399,
    419,
    351,
    417,
  ];
  static const _chin = [
    32,
    194,
    83,
    18,
    313,
    418,
    262,
    400,
    377,
    152,
    148,
    176,
  ];
  static const _cheekRight = [
    116,
    117,
    118,
    119,
    100,
    126,
    209,
    203,
    206,
    216,
    212,
    214,
    135,
    172,
    58,
    132,
    93,
  ];
  static const _cheekLeft = [
    345,
    346,
    347,
    348,
    329,
    355,
    429,
    423,
    426,
    436,
    432,
    434,
    364,
    397,
    288,
    361,
    323,
  ];
  static const _lips = [
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
  static const _eyeRight = [
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
  static const _eyeLeft = [
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
  static const _faceOval = [
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

  static const normFaceWidth =
      300.0; // the sharpness is measured at this face width
  static const _erode =
      0.012; // zone edges shrink by this fraction of the face width
  static const _skinDeltaE = 20.0;

  /// [mesh] has at least 478 points. [otherWidths]: widths of the other faces.
  static PhotoMetrics measure(
    PhotoPixels px,
    List<Offset> mesh, {
    List<double> otherWidths = const [],
  }) {
    final faceW = (mesh[454] - mesh[234]).distance;
    // the bounding box of everything we look at: the face oval, a little wider
    final ov = [for (final i in _faceOval) mesh[i]];
    var minX = ov.first.dx,
        maxX = ov.first.dx,
        minY = ov.first.dy,
        maxY = ov.first.dy;
    for (final p in ov) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    final x0 = math.max(0, minX.floor() - 4),
        y0 = math.max(0, minY.floor() - 4);
    final x1 = math.min(px.width, maxX.ceil() + 4),
        y1 = math.min(px.height, maxY.ceil() + 4);
    final w = x1 - x0, h = y1 - y0;
    if (w < 16 || h < 16 || faceW < 1) return _empty(faceW, otherWidths, mesh);
    final box = _Box(x0, y0, w, h);

    final luma = Uint8List(w * h);
    final lL = Float32List(w * h),
        lA = Float32List(w * h),
        lB = Float32List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final o = ((y0 + y) * px.width + (x0 + x)) * 4;
        final r = px.rgba[o], g = px.rgba[o + 1], b = px.rgba[o + 2];
        final i = y * w + x;
        luma[i] = (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
        _lab(r, g, b, lL, lA, lB, i);
      }
    }

    final k = math.max(1, (_erode * faceW).round());
    _Mask zone(List<int> loop) => _fill(box, [for (final i in loop) mesh[i]]);
    final holes = _dilate(
      _union([
        _fill(box, [for (final i in _lips) mesh[i]]),
        _fill(box, [for (final i in _eyeRight) mesh[i]]),
        _fill(box, [for (final i in _eyeLeft) mesh[i]]),
      ]),
      k,
    );
    _Mask finish(_Mask m) => _subtract(_erodeMask(m, k), holes);
    final fh = finish(zone(_forehead));
    final nz = finish(zone(_nose));
    final ch = finish(zone(_chin));
    final cr = finish(zone(_cheekRight));
    final cl = finish(zone(_cheekLeft));
    final skin = _union([fh, nz, ch, cr, cl]);

    // --- sharpness: face bounding box, grey, rescaled to normFaceWidth, variance of the Laplacian
    final sharp = _sharpness(luma, w, h, ov, box, faceW);

    // --- exposure inside the face oval and the skin zones
    final oval = _fill(box, ov);
    final hist = List<int>.filled(256, 0);
    var nOval = 0;
    for (var i = 0; i < oval.data.length; i++) {
      if (oval.data[i] != 0) {
        hist[luma[i]]++;
        nOval++;
      }
    }
    final p95 = nOval == 0
        ? double.nan
        : _percentileFromHist(hist, nOval, 0.95);
    var nSkin = 0, clipped = 0, crushed = 0;
    final chroma = <double>[];
    for (var i = 0; i < skin.data.length; i++) {
      if (skin.data[i] == 0) continue;
      nSkin++;
      if (luma[i] >= 250) clipped++;
      if (luma[i] <= 12) crushed++;
      chroma.add(math.sqrt(lA[i] * lA[i] + lB[i] * lB[i]));
    }
    final chromaMedian = chroma.isEmpty ? double.nan : _median(chroma);

    // --- side light: mean L* of the two cheeks
    var lrAsym = double.nan;
    final nl = _count(cl), nr = _count(cr);
    if (nl > 50 && nr > 50) {
      final a = _meanOver(cl, lL), b = _meanOver(cr, lL);
      lrAsym = (a - b).abs() / math.max(1e-6, (a + b) / 2);
    }

    // --- head pose along the eye line, so a tilted head is not read as a turned one
    final eye = mesh[263] - mesh[33];
    final u = eye / eye.distance;
    double dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;
    final width = dot(mesh[454] - mesh[234], u);
    final ratio = dot(mesh[4] - mesh[234], u) / width;
    final yaw = (ratio - 0.5).abs();
    final roll = math.atan2(eye.dy, eye.dx) * 180 / math.pi;

    // --- eyes against the cheeks
    final eyes = _union([
      _fill(box, [for (final i in _eyeRight) mesh[i]]),
      _fill(box, [for (final i in _eyeLeft) mesh[i]]),
    ]);
    final cheeks = _union([cr, cl]);
    var eyeDark = double.nan, eyeContrast = double.nan;
    if (_count(eyes) > 0 && _count(cheeks) >= 50) {
      final ref = math.max(
        1.0,
        _median([
          for (var i = 0; i < cheeks.data.length; i++)
            if (cheeks.data[i] != 0) luma[i].toDouble(),
        ]),
      );
      final ev = [
        for (var i = 0; i < eyes.data.length; i++)
          if (eyes.data[i] != 0) luma[i].toDouble(),
      ];
      final mean = ev.reduce((a, b) => a + b) / ev.length;
      final varc =
          ev.fold<double>(0, (s, v) => s + (v - mean) * (v - mean)) / ev.length;
      eyeDark = _median(ev) / ref;
      eyeContrast = math.sqrt(varc) / ref;
    }

    // --- how much of cheeks, forehead and nose is the colour of this face's skin
    final zmask = _union([cr, cl, fh, nz]);
    var skinVisible = double.nan;
    final nz2 = _count(zmask);
    if (nz2 >= 100) {
      final ls = <double>[], as = <double>[], bs = <double>[];
      for (var i = 0; i < zmask.data.length; i++) {
        if (zmask.data[i] == 0) continue;
        ls.add(lL[i]);
        as.add(lA[i]);
        bs.add(lB[i]);
      }
      final rl = _median(ls), ra = _median(as), rb = _median(bs);
      var near = 0;
      for (var j = 0; j < ls.length; j++) {
        final d = math.sqrt(
          math.pow(ls[j] - rl, 2) +
              math.pow(as[j] - ra, 2) +
              math.pow(bs[j] - rb, 2),
        );
        if (d <= _skinDeltaE) near++;
      }
      skinVisible = near / ls.length;
    }

    return PhotoMetrics(
      faceCount: 1 + otherWidths.length,
      facePx: faceW,
      sharpness: sharp,
      faceP95Luma: p95,
      skinChroma: chromaMedian,
      clippedPct: nSkin == 0 ? double.nan : 100.0 * clipped / nSkin,
      crushedPct: nSkin == 0 ? double.nan : 100.0 * crushed / nSkin,
      lrAsym: lrAsym,
      yawOffset: yaw,
      rollDeg: roll,
      secondFaceRatio: otherWidths.isEmpty
          ? 0.0
          : otherWidths.reduce(math.max) / faceW,
      eyeDarkRatio: eyeDark,
      eyeContrast: eyeContrast,
      skinVisible: skinVisible,
    );
  }

  static PhotoMetrics _empty(
    double faceW,
    List<double> other,
    List<Offset> mesh,
  ) => PhotoMetrics(
    faceCount: 1 + other.length,
    facePx: faceW,
    sharpness: 0,
    faceP95Luma: double.nan,
    skinChroma: double.nan,
    clippedPct: double.nan,
    crushedPct: double.nan,
    lrAsym: double.nan,
    yawOffset: double.nan,
    rollDeg: 0,
    secondFaceRatio: other.isEmpty
        ? 0.0
        : other.reduce(math.max) / math.max(1, faceW),
    eyeDarkRatio: double.nan,
    eyeContrast: double.nan,
    skinVisible: double.nan,
  );

  // ---------------------------------------------------------------- colour

  /// sRGB (0-255) to CIELAB (D65), real L* 0-100 and a*, b*.
  static void _lab(
    int r8,
    int g8,
    int b8,
    Float32List lL,
    Float32List lA,
    Float32List lB,
    int i,
  ) {
    double lin(int c) {
      final v = c / 255.0;
      return v <= 0.04045
          ? v / 12.92
          : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    }

    final r = lin(r8), g = lin(g8), b = lin(b8);
    final x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047;
    final y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b;
    final z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883;
    double f(double t) =>
        t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
    final fx = f(x), fy = f(y), fz = f(z);
    lL[i] = 116 * fy - 16;
    lA[i] = 500 * (fx - fy);
    lB[i] = 200 * (fy - fz);
  }

  // ---------------------------------------------------------------- statistics

  static double _median(List<double> v) {
    final s = [...v]..sort();
    final n = s.length;
    return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
  }

  static double _percentileFromHist(List<int> hist, int n, double q) {
    final pos = q * (n - 1);
    final lo = pos.floor(), hi = pos.ceil();
    double at(int idx) {
      var acc = 0;
      for (var v = 0; v < 256; v++) {
        acc += hist[v];
        if (idx < acc) return v.toDouble();
      }
      return 255;
    }

    final a = at(lo), b = at(hi);
    return a + (b - a) * (pos - lo);
  }

  static int _count(_Mask m) {
    var n = 0;
    for (final v in m.data) {
      if (v != 0) n++;
    }
    return n;
  }

  static double _meanOver(_Mask m, Float32List v) {
    var s = 0.0, n = 0;
    for (var i = 0; i < m.data.length; i++) {
      if (m.data[i] != 0) {
        s += v[i];
        n++;
      }
    }
    return n == 0 ? double.nan : s / n;
  }

  // ---------------------------------------------------------------- sharpness

  static double _sharpness(
    Uint8List luma,
    int w,
    int h,
    List<Offset> oval,
    _Box box,
    double faceW,
  ) {
    var minX = oval.first.dx,
        maxX = oval.first.dx,
        minY = oval.first.dy,
        maxY = oval.first.dy;
    for (final p in oval) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    final cx0 = math.max(box.x0, minX.floor()),
        cy0 = math.max(box.y0, minY.floor());
    final cx1 = math.min(box.x0 + w, maxX.ceil()),
        cy1 = math.min(box.y0 + h, maxY.ceil());
    final cw = cx1 - cx0, ch = cy1 - cy0;
    if (cw < 8 || ch < 8) return 0.0;
    final src = Float32List(cw * ch);
    for (var y = 0; y < ch; y++) {
      for (var x = 0; x < cw; x++) {
        src[y * cw + x] = luma[(cy0 - box.y0 + y) * w + (cx0 - box.x0 + x)]
            .toDouble();
      }
    }
    final s = normFaceWidth / faceW;
    final tw = math.max(4, (cw * s).round()),
        th = math.max(4, (ch * s).round());
    final img = s < 1
        ? _resizeArea(src, cw, ch, tw, th)
        : _resizeCubic(src, cw, ch, tw, th);
    // 3x3 Laplacian [[0,1,0],[1,-4,1],[0,1,0]], border reflected without repeating the edge pixel
    int refl(int i, int n) => i < 0 ? -i : (i >= n ? 2 * n - 2 - i : i);
    var sum = 0.0, sum2 = 0.0;
    for (var y = 0; y < th; y++) {
      for (var x = 0; x < tw; x++) {
        final c = img[y * tw + x];
        final v =
            img[refl(y - 1, th) * tw + x] +
            img[refl(y + 1, th) * tw + x] +
            img[y * tw + refl(x - 1, tw)] +
            img[y * tw + refl(x + 1, tw)] -
            4 * c;
        sum += v;
        sum2 += v * v;
      }
    }
    final n = tw * th;
    final mean = sum / n;
    return sum2 / n - mean * mean;
  }

  /// Area-averaging downscale (like OpenCV INTER_AREA).
  static Float32List _resizeArea(
    Float32List src,
    int sw,
    int sh,
    int tw,
    int th,
  ) {
    final out = Float32List(tw * th);
    final fx = sw / tw, fy = sh / th;
    for (var y = 0; y < th; y++) {
      final ya = y * fy, yb = (y + 1) * fy;
      for (var x = 0; x < tw; x++) {
        final xa = x * fx, xb = (x + 1) * fx;
        var acc = 0.0, wsum = 0.0;
        for (var j = ya.floor(); j < math.min(sh, yb.ceil()); j++) {
          final wy = math.min(yb, j + 1) - math.max(ya, j);
          for (var i = xa.floor(); i < math.min(sw, xb.ceil()); i++) {
            final wx = math.min(xb, i + 1) - math.max(xa, i);
            final wgt = wx * wy;
            acc += src[j * sw + i] * wgt;
            wsum += wgt;
          }
        }
        out[y * tw + x] = acc / wsum;
      }
    }
    return out;
  }

  /// Bicubic upscale like OpenCV INTER_CUBIC (a = -0.75, edge pixels repeated). The
  /// sharpness number depends on the interpolation, so it must match the stand's.
  static Float32List _resizeCubic(
    Float32List src,
    int sw,
    int sh,
    int tw,
    int th,
  ) {
    const a = -0.75;
    final out = Float32List(tw * th);
    final wxs = List<List<double>>.generate(tw, (_) => List.filled(4, 0.0));
    final xis = List<int>.filled(tw, 0);
    for (var x = 0; x < tw; x++) {
      final fx = (x + 0.5) * sw / tw - 0.5;
      final x0 = fx.floor();
      xis[x] = x0;
      final t = fx - x0;
      wxs[x][0] = ((a * (t + 1) - 5 * a) * (t + 1) + 8 * a) * (t + 1) - 4 * a;
      wxs[x][1] = ((a + 2) * t - (a + 3)) * t * t + 1;
      wxs[x][2] = ((a + 2) * (1 - t) - (a + 3)) * (1 - t) * (1 - t) + 1;
      wxs[x][3] = 1 - wxs[x][0] - wxs[x][1] - wxs[x][2];
    }
    int clampI(int i, int n) => i < 0 ? 0 : (i >= n ? n - 1 : i);
    for (var y = 0; y < th; y++) {
      final fy = (y + 0.5) * sh / th - 0.5;
      final y0 = fy.floor();
      final t = fy - y0;
      final wy0 = ((a * (t + 1) - 5 * a) * (t + 1) + 8 * a) * (t + 1) - 4 * a;
      final wy1 = ((a + 2) * t - (a + 3)) * t * t + 1;
      final wy2 = ((a + 2) * (1 - t) - (a + 3)) * (1 - t) * (1 - t) + 1;
      final wy = [wy0, wy1, wy2, 1 - wy0 - wy1 - wy2];
      for (var x = 0; x < tw; x++) {
        var acc = 0.0;
        for (var j = 0; j < 4; j++) {
          final row = clampI(y0 - 1 + j, sh) * sw;
          var r = 0.0;
          for (var i = 0; i < 4; i++) {
            r += src[row + clampI(xis[x] - 1 + i, sw)] * wxs[x][i];
          }
          acc += r * wy[j];
        }
        out[y * tw + x] = acc;
      }
    }
    return out;
  }

  // ---------------------------------------------------------------- masks

  /// Even-odd scanline fill of the polygon, pixel centres, inside [box].
  static _Mask _fill(_Box box, List<Offset> poly) {
    final m = _Mask(box);
    final n = poly.length;
    for (var y = 0; y < box.h; y++) {
      final yc = box.y0 + y + 0.5;
      final xs = <double>[];
      for (var i = 0; i < n; i++) {
        final a = poly[i], b = poly[(i + 1) % n];
        if ((a.dy <= yc && b.dy > yc) || (b.dy <= yc && a.dy > yc)) {
          xs.add(a.dx + (yc - a.dy) * (b.dx - a.dx) / (b.dy - a.dy));
        }
      }
      xs.sort();
      for (var k = 0; k + 1 < xs.length; k += 2) {
        final from = math.max(0, (xs[k] - 0.5 - box.x0).ceil());
        final to = math.min(box.w - 1, (xs[k + 1] - 0.5 - box.x0).floor());
        for (var x = from; x <= to; x++) {
          m.data[y * box.w + x] = 1;
        }
      }
    }
    return m;
  }

  static _Mask _union(List<_Mask> ms) {
    final out = _Mask(ms.first.box);
    for (final m in ms) {
      for (var i = 0; i < out.data.length; i++) {
        if (m.data[i] != 0) out.data[i] = 1;
      }
    }
    return out;
  }

  static _Mask _subtract(_Mask a, _Mask b) {
    final out = _Mask(a.box);
    for (var i = 0; i < out.data.length; i++) {
      out.data[i] = a.data[i] != 0 && b.data[i] == 0 ? 1 : 0;
    }
    return out;
  }

  static _Mask _dilate(_Mask m, int k) => _morph(m, k, true);
  static _Mask _erodeMask(_Mask m, int k) => _morph(m, k, false);

  /// Square structuring element of radius [k], two separable passes.
  static _Mask _morph(_Mask m, int k, bool grow) {
    final w = m.box.w, h = m.box.h;
    final tmp = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var hit = grow ? 0 : 1;
        for (var d = -k; d <= k; d++) {
          final xx = x + d;
          final v = (xx < 0 || xx >= w) ? 0 : m.data[y * w + xx];
          if (grow) {
            if (v != 0) {
              hit = 1;
              break;
            }
          } else if (v == 0) {
            hit = 0;
            break;
          }
        }
        tmp[y * w + x] = hit;
      }
    }
    final out = _Mask(m.box);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var hit = grow ? 0 : 1;
        for (var d = -k; d <= k; d++) {
          final yy = y + d;
          final v = (yy < 0 || yy >= h) ? 0 : tmp[yy * w + x];
          if (grow) {
            if (v != 0) {
              hit = 1;
              break;
            }
          } else if (v == 0) {
            hit = 0;
            break;
          }
        }
        out.data[y * w + x] = hit;
      }
    }
    return out;
  }
}

class _Box {
  const _Box(this.x0, this.y0, this.w, this.h);
  final int x0, y0, w, h;
}

class _Mask {
  _Mask(this.box) : data = Uint8List(box.w * box.h);
  final _Box box;
  final Uint8List data;
}
