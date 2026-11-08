import 'dart:ui' show Offset, Size;

/// How the rotated camera image is fitted into the preview box.
enum FaceFit { cover, contain }

/// Maps points between the raw camera image (sensor pixels) and a preview box,
/// applying the camera rotation, the front-camera mirror, and the cover/contain
/// fit of the preview.
///
/// The camera image is first rotated by [rotationDegrees] clockwise (the angle
/// the platform reports to make the frame upright), then mirrored horizontally
/// when [mirror] is true (the front camera), then scaled and centered into
/// [previewSize] with [fit].
class FaceCoordinateTransform {
  const FaceCoordinateTransform({
    required this.imageSize,
    required this.previewSize,
    this.rotationDegrees = 0,
    this.mirror = false,
    this.fit = FaceFit.cover,
  });

  final Size imageSize;
  final Size previewSize;
  final int rotationDegrees;
  final bool mirror;
  final FaceFit fit;

  Size get _rotatedSize => rotationDegrees % 180 == 0
      ? imageSize
      : Size(imageSize.height, imageSize.width);

  double get _scale {
    if (_rotatedSize.width <= 0 || _rotatedSize.height <= 0) return 1;
    final sx = previewSize.width / _rotatedSize.width;
    final sy = previewSize.height / _rotatedSize.height;
    return fit == FaceFit.cover ? (sx > sy ? sx : sy) : (sx < sy ? sx : sy);
  }

  Offset get _offset {
    final s = _scale;
    return Offset(
      (previewSize.width - _rotatedSize.width * s) / 2,
      (previewSize.height - _rotatedSize.height * s) / 2,
    );
  }

  /// Rotates a sensor point clockwise into upright (unmirrored) coordinates.
  Offset _rotate(Offset p) {
    final w = imageSize.width, h = imageSize.height;
    switch (rotationDegrees % 360) {
      case 90:
        return Offset(h - p.dy, p.dx);
      case 180:
        return Offset(w - p.dx, h - p.dy);
      case 270:
        return Offset(p.dy, w - p.dx);
      default:
        return p;
    }
  }

  /// Un-rotates an upright point back into sensor coordinates.
  Offset _unrotate(Offset p) {
    final w = imageSize.width, h = imageSize.height;
    switch (rotationDegrees % 360) {
      case 90:
        return Offset(p.dy, h - p.dx);
      case 180:
        return Offset(w - p.dx, h - p.dy);
      case 270:
        return Offset(w - p.dy, p.dx);
      default:
        return p;
    }
  }

  Offset _mirrorX(Offset p) => Offset(_rotatedSize.width - p.dx, p.dy);

  /// Image (sensor) point -> preview point.
  Offset toPreview(Offset image) {
    var p = _rotate(image);
    if (mirror) p = _mirrorX(p);
    final s = _scale;
    return _offset + Offset(p.dx * s, p.dy * s);
  }

  /// Preview point -> image (sensor) point. Inverse of [toPreview].
  Offset toImage(Offset preview) {
    final s = _scale;
    var p = Offset(
      (preview.dx - _offset.dx) / s,
      (preview.dy - _offset.dy) / s,
    );
    if (mirror) p = _mirrorX(p); // mirror is its own inverse
    return _unrotate(p);
  }
}
