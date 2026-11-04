import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'virtual_makeup_controller.dart';

/// The photo with the result, the original, or both side by side, and (while
/// the protection is edited) the protected area drawn on it.
class MakeupPhotoView extends StatefulWidget {
  const MakeupPhotoView({
    super.key,
    required this.controller,
    required this.editing,
    required this.brushRadius,
    required this.erase,
    required this.onDrawing,
  });

  final VirtualMakeupController controller;
  final bool editing;

  /// Brush radius as a share of the photo's short side.
  final double brushRadius;
  final bool erase;
  final ValueChanged<bool> onDrawing;

  @override
  State<MakeupPhotoView> createState() => _MakeupPhotoViewState();
}

class _MakeupPhotoViewState extends State<MakeupPhotoView> {
  bool _holdOriginal = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final face = c.face;
    final original = c.originalImage;
    if (face == null || original == null) return const SizedBox.shrink();
    final iw = face.image.width.toDouble(), ih = face.image.height.toDouble();
    return LayoutBuilder(
      builder: (context, box) {
        final maxH = math.min(
          box.maxWidth * 1.25,
          MediaQuery.sizeOf(context).height * 0.5,
        );
        final scale = math.min(box.maxWidth / iw, maxH / ih);
        final w = iw * scale, h = ih * scale;
        final mode = _holdOriginal ? CompareMode.original : c.compare;

        Offset toImage(Offset local) =>
            Offset(local.dx / scale, local.dy / scale);
        double radius() => widget.brushRadius * math.min(iw, ih);

        return Center(
          child: SizedBox(
            key: const Key('vm-photo'),
            width: w,
            height: h,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) {
                  if (widget.editing) {
                    widget.onDrawing(true);
                    c.strokeStart(
                      toImage(e.localPosition),
                      radius(),
                      erase: widget.erase,
                    );
                  } else if (c.compare == CompareMode.split) {
                    c.setSplit(e.localPosition.dx / w);
                  }
                },
                onPointerMove: (e) {
                  if (widget.editing) {
                    c.strokeMove(
                      toImage(e.localPosition),
                      radius(),
                      erase: widget.erase,
                    );
                  } else if (c.compare == CompareMode.split) {
                    c.setSplit(e.localPosition.dx / w);
                  }
                },
                onPointerUp: (_) {
                  if (widget.editing) {
                    c.strokeEnd();
                    widget.onDrawing(false);
                  }
                },
                onPointerCancel: (_) {
                  if (widget.editing) {
                    c.strokeEnd();
                    widget.onDrawing(false);
                  }
                },
                child: GestureDetector(
                  // hold the photo to see the original (not while drawing)
                  onLongPressStart: widget.editing
                      ? null
                      : (_) => setState(() => _holdOriginal = true),
                  onLongPressEnd: widget.editing
                      ? null
                      : (_) => setState(() => _holdOriginal = false),
                  child: CustomPaint(
                    painter: _PhotoPainter(
                      original: original,
                      result: c.resultImage,
                      mode: mode,
                      split: c.split,
                      protection: widget.editing ? c.protectionOverlay : null,
                      suggestion: widget.editing ? c.suggestionOverlay : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PhotoPainter extends CustomPainter {
  _PhotoPainter({
    required this.original,
    required this.result,
    required this.mode,
    required this.split,
    required this.protection,
    required this.suggestion,
  });

  final ui.Image original;
  final ui.Image? result;
  final CompareMode mode;
  final double split;
  final ui.Image? protection;
  final ui.Image? suggestion;

  void _draw(Canvas canvas, ui.Image img, Size size, {Rect? clip}) {
    canvas.save();
    if (clip != null) canvas.clipRect(clip);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final res = result ?? original;
    switch (mode) {
      case CompareMode.original:
        _draw(canvas, original, size);
      case CompareMode.result:
        _draw(canvas, res, size);
      case CompareMode.split:
        final x = size.width * split;
        _draw(canvas, res, size);
        _draw(
          canvas,
          original,
          size,
          clip: Rect.fromLTWH(0, 0, x, size.height),
        );
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          Paint()
            ..color = Colors.white
            ..strokeWidth = 2,
        );
        canvas.drawCircle(
          Offset(x, size.height / 2),
          14,
          Paint()..color = Colors.white,
        );
        canvas.drawCircle(
          Offset(x, size.height / 2),
          14,
          Paint()
            ..color = Colors.black45
            ..style = PaintingStyle.stroke,
        );
    }
    if (protection != null) _draw(canvas, protection!, size);
    if (suggestion != null) _draw(canvas, suggestion!, size);
  }

  @override
  bool shouldRepaint(covariant _PhotoPainter old) =>
      old.original != original ||
      old.result != result ||
      old.mode != mode ||
      old.split != split ||
      old.protection != protection ||
      old.suggestion != suggestion;
}
