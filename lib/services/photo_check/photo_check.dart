import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:cosmetix/services/photo_check/face_finder.dart';
import 'package:cosmetix/services/photo_check/photo_metrics.dart';
import 'package:cosmetix/services/photo_check/photo_pixels.dart';
import 'package:cosmetix/services/photo_check/photo_rules.dart';

export 'package:cosmetix/services/photo_check/face_finder.dart';
export 'package:cosmetix/services/photo_check/photo_metrics.dart';
export 'package:cosmetix/services/photo_check/photo_pixels.dart';
export 'package:cosmetix/services/photo_check/photo_rules.dart';

/// What the check found: the verdict and, when a face was measured, the numbers.
class PhotoCheckResult {
  const PhotoCheckResult(this.verdict, [this.metrics]);

  final PhotoVerdict verdict;
  final PhotoMetrics? metrics;
}

/// The local check that decides whether a photo may go to the AI at all.
///
/// Everything here runs on the phone BEFORE any network call: it decodes the
/// file, looks for faces, measures the main face and applies the rules. It never
/// sends the photo anywhere, and a photo that was not checked (a damaged file, a
/// failing detector) is a rejected photo: fail closed.
class PhotoCheck {
  PhotoCheck(this._finder, {this.maxSide = 2048});

  final PhotoFaceFinder _finder;
  final int maxSide;

  Future<void> dispose() => _finder.dispose();

  /// [bytes] is the file as picked (JPEG, PNG, HEIC...).
  Future<PhotoCheckResult> run(Uint8List bytes) async {
    final PhotoPixels photo;
    try {
      photo = await PhotoPixels.decode(bytes, maxSide: maxSide);
    } on FormatException {
      return PhotoCheckResult(const PhotoVerdict.reject(PhotoIssue.unreadable));
    } catch (_) {
      return PhotoCheckResult(const PhotoVerdict.reject(PhotoIssue.unreadable));
    }
    return checkPixels(photo);
  }

  /// The same check on pixels that are already decoded (tests, tools).
  Future<PhotoCheckResult> checkPixels(PhotoPixels photo) async {
    final List<List<Offset>> faces;
    try {
      faces = await _finder.find(photo);
    } catch (_) {
      return PhotoCheckResult(
        const PhotoVerdict.reject(PhotoIssue.checkFailed),
      );
    }
    if (faces.isEmpty) {
      return PhotoCheckResult(const PhotoVerdict.reject(PhotoIssue.noFace));
    }
    // the finder's order is arbitrary: the main face is the largest
    double area(List<Offset> f) {
      var minX = f.first.dx, maxX = minX, minY = f.first.dy, maxY = minY;
      for (final p in f) {
        minX = math.min(minX, p.dx);
        maxX = math.max(maxX, p.dx);
        minY = math.min(minY, p.dy);
        maxY = math.max(maxY, p.dy);
      }
      return (maxX - minX) * (maxY - minY);
    }

    final sorted = [...faces]..sort((a, b) => area(b).compareTo(area(a)));
    final main = sorted.first;
    final others = [for (final f in sorted.skip(1)) (f[454] - f[234]).distance];
    try {
      final m = PhotoMeasure.measure(photo, main, otherWidths: others);
      return PhotoCheckResult(PhotoThresholds.judge(m), m);
    } catch (_) {
      return PhotoCheckResult(
        const PhotoVerdict.reject(PhotoIssue.checkFailed),
      );
    }
  }
}
