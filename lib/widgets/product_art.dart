import 'package:flutter/material.dart';

/// Local placeholder illustration of a cosmetic product, drawn with solid
/// colors only (used instead of photos that cannot be exported from Figma).
class ProductArt extends StatelessWidget {
  const ProductArt({
    super.key,
    required this.art,
    required this.color,
    this.radius = 12,
  });

  final String art;
  final int color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final base = Color(color);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(
        color: Color.lerp(base, Colors.white, 0.8)!,
        child: SizedBox.expand(
          child: CustomPaint(painter: _ArtPainter(art, base)),
        ),
      ),
    );
  }
}

class _ArtPainter extends CustomPainter {
  _ArtPainter(this.art, this.base);

  final String art;
  final Color base;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide * 0.6;
    final c = size.center(Offset.zero);
    final dark = Color.lerp(base, Colors.black, 0.28)!;
    final light = Color.lerp(base, Colors.white, 0.5)!;
    final paper = Color.lerp(base, Colors.white, 0.72)!;
    final fill = Paint()..style = PaintingStyle.fill;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = dark.withValues(alpha: 0.5);

    RRect rr(Offset center, double w, double h, double r) =>
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: w, height: h),
          Radius.circular(r),
        );

    switch (art) {
      case 'palette':
        final body = rr(c, s * 1.35, s * 0.95, s * 0.09);
        canvas.drawRRect(body, fill..color = paper);
        canvas.drawRRect(body, line);
        const cols = 4, rows = 2;
        final pan = s * 0.26;
        final gap = s * 0.06;
        final startX = c.dx - (cols * pan + (cols - 1) * gap) / 2;
        final startY = c.dy - (rows * pan + (rows - 1) * gap) / 2;
        for (var i = 0; i < cols * rows; i++) {
          final r = i ~/ cols, col = i % cols;
          final shade = Color.lerp(
            i.isEven ? dark : base,
            light,
            (col * 0.22 + r * 0.1).clamp(0, 1),
          )!;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(
                startX + col * (pan + gap),
                startY + r * (pan + gap),
                pan,
                pan,
              ),
              Radius.circular(pan * 0.22),
            ),
            fill..color = shade,
          );
        }
      case 'tube':
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.rotate(-0.45);
        canvas.drawRRect(
          rr(Offset(0, s * 0.18), s * 0.3, s * 0.78, s * 0.08),
          fill..color = base,
        );
        canvas.drawRRect(
          rr(Offset(0, -s * 0.34), s * 0.34, s * 0.3, s * 0.06),
          fill..color = dark,
        );
        canvas.drawRRect(
          rr(Offset(0, s * 0.45), s * 0.22, s * 0.12, s * 0.04),
          fill..color = light,
        );
        canvas.restore();
      case 'perfume':
        canvas.drawRRect(
          rr(c.translate(0, s * 0.12), s * 0.72, s * 0.72, s * 0.1),
          fill..color = paper,
        );
        canvas.drawRRect(
          rr(c.translate(0, s * 0.12), s * 0.72, s * 0.72, s * 0.1),
          line,
        );
        canvas.drawRRect(
          rr(c.translate(0, s * 0.12), s * 0.5, s * 0.5, s * 0.06),
          fill..color = base,
        );
        canvas.drawRRect(
          rr(c.translate(0, -s * 0.42), s * 0.28, s * 0.2, s * 0.04),
          fill..color = dark,
        );
        canvas.drawRect(
          Rect.fromCenter(
            center: c.translate(0, -s * 0.28),
            width: s * 0.12,
            height: s * 0.1,
          ),
          fill..color = light,
        );
      case 'compact':
        canvas.drawCircle(c, s * 0.52, fill..color = paper);
        canvas.drawCircle(c, s * 0.52, line);
        canvas.drawCircle(c, s * 0.36, fill..color = base);
        canvas.drawCircle(
          c.translate(-s * 0.12, -s * 0.12),
          s * 0.08,
          fill..color = light,
        );
      case 'cream':
        canvas.drawRRect(
          rr(c.translate(0, s * 0.14), s * 0.8, s * 0.5, s * 0.1),
          fill..color = base,
        );
        canvas.drawRRect(
          rr(c.translate(0, -s * 0.18), s * 0.86, s * 0.24, s * 0.06),
          fill..color = dark,
        );
        canvas.drawRRect(
          rr(c.translate(0, s * 0.14), s * 0.4, s * 0.2, s * 0.04),
          fill..color = light,
        );
      case 'box':
        canvas.drawRRect(
          rr(c.translate(0, s * 0.08), s * 0.9, s * 0.8, s * 0.06),
          fill..color = base,
        );
        canvas.drawRect(
          Rect.fromCenter(
            center: c.translate(0, s * 0.08),
            width: s * 0.14,
            height: s * 0.8,
          ),
          fill..color = light,
        );
        canvas.drawRRect(
          rr(c.translate(0, -s * 0.36), s * 0.98, s * 0.2, s * 0.05),
          fill..color = dark,
        );
        canvas.drawCircle(
          c.translate(-s * 0.12, -s * 0.52),
          s * 0.1,
          fill..color = light,
        );
        canvas.drawCircle(
          c.translate(s * 0.12, -s * 0.52),
          s * 0.1,
          fill..color = light,
        );
      default: // bottle with a dropper
        canvas.drawRRect(
          rr(c.translate(0, s * 0.18), s * 0.56, s * 0.7, s * 0.1),
          fill..color = base,
        );
        canvas.drawRRect(
          rr(c.translate(0, s * 0.18), s * 0.34, s * 0.3, s * 0.04),
          fill..color = paper,
        );
        canvas.drawRect(
          Rect.fromCenter(
            center: c.translate(0, -s * 0.24),
            width: s * 0.2,
            height: s * 0.14,
          ),
          fill..color = dark,
        );
        canvas.drawRRect(
          rr(c.translate(0, -s * 0.42), s * 0.26, s * 0.22, s * 0.1),
          fill..color = dark,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _ArtPainter old) =>
      old.art != art || old.base != base;
}
