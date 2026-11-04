import 'dart:math' as math;
import 'dart:typed_data';

/// The skin the user wants left exactly as it is (acne, scars, redness, moles,
/// anything else). Where the mask is 255 the makeup is not applied at all and
/// the pixel stays byte for byte as in the photo.
///
/// The mask is edited by hand (brush and eraser); [merge] adds a suggestion the
/// user accepted. The suggestion is a hint, never a diagnosis.
class ProtectionMask {
  ProtectionMask(this.width, this.height) : data = Uint8List(width * height);

  final int width;
  final int height;
  final Uint8List data;

  static const _maxUndo = 30;
  final List<_Snapshot> _undo = [];
  final List<_Snapshot> _redo = [];

  bool get isEmpty => !data.any((v) => v != 0);

  /// Share of the photo that is protected, 0..1.
  double get coverage {
    var n = 0;
    for (final v in data) {
      if (v != 0) n++;
    }
    return n / data.length;
  }

  /// 0..1 at a pixel.
  double at(int x, int y) => data[y * width + x] / 255;

  /// Call before a stroke: the stroke can then be undone as one step.
  void beginStroke() {
    _undo.add(_Snapshot(Uint8List.fromList(data)));
    if (_undo.length > _maxUndo) _undo.removeAt(0);
    _redo.clear();
  }

  /// Paints (or erases) a round dab. [hardness] 1 = hard edge, 0 = very soft.
  void dab(
    double cx,
    double cy,
    double radius, {
    bool erase = false,
    double hardness = 0.7,
  }) {
    final x0 = math.max(0, (cx - radius).floor());
    final x1 = math.min(width - 1, (cx + radius).ceil());
    final y0 = math.max(0, (cy - radius).floor());
    final y1 = math.min(height - 1, (cy + radius).ceil());
    final inner = radius * hardness.clamp(0.0, 0.99);
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final d = math.sqrt(
          (x + 0.5 - cx) * (x + 0.5 - cx) + (y + 0.5 - cy) * (y + 0.5 - cy),
        );
        if (d > radius) continue;
        final cover = d <= inner ? 1.0 : 1 - (d - inner) / (radius - inner);
        final i = y * width + x;
        if (erase) {
          data[i] = math.max(0, data[i] - (cover * 255).round());
        } else {
          data[i] = math.max(data[i], (cover * 255).round());
        }
      }
    }
  }

  /// A line of dabs from one point to the next (so fast strokes have no gaps).
  void stroke(
    double x0,
    double y0,
    double x1,
    double y1,
    double radius, {
    bool erase = false,
  }) {
    final dist = math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
    final steps = math.max(1, (dist / math.max(1, radius * 0.35)).ceil());
    for (var s = 0; s <= steps; s++) {
      final t = s / steps;
      dab(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, radius, erase: erase);
    }
  }

  /// Adds the accepted pixels of [suggestion] (same size, 0 or 255).
  void merge(Uint8List suggestion) {
    assert(suggestion.length == data.length);
    beginStroke();
    for (var i = 0; i < data.length; i++) {
      if (suggestion[i] > data[i]) data[i] = suggestion[i];
    }
  }

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_Snapshot(Uint8List.fromList(data)));
    data.setAll(0, _undo.removeLast().data);
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_Snapshot(Uint8List.fromList(data)));
    data.setAll(0, _redo.removeLast().data);
  }

  void clear() {
    if (isEmpty) return;
    beginStroke();
    data.fillRange(0, data.length, 0);
  }

  ProtectionMask copy() {
    final m = ProtectionMask(width, height);
    m.data.setAll(0, data);
    return m;
  }
}

class _Snapshot {
  _Snapshot(this.data);
  final Uint8List data;
}
