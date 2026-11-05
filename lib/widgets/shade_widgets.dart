import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_dimensions.dart';
import 'package:cosmetix/models/palette_models.dart';

/// Small building blocks for shades and palettes, made from the app's own
/// tokens (`context.pal`, `AppColors`, `AppDimensions`) so they follow the
/// light and the dark theme.

/// A tidy one-line note: "the colour is approximate". It is the same note
/// everywhere a colour is not the manufacturer's or our own measured one.
class ApproxNote extends StatelessWidget {
  const ApproxNote({super.key, this.text, this.compact = false});

  /// Replaces the standard text (for a longer explanation).
  final String? text;

  /// No background: just the icon and the words (inside a card).
  final bool compact;

  /// The standard wording, one place for every screen.
  static String get standard => tr('Приблизительная передача оттенка');

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(Icons.info_outline, size: 15, color: pal.subtext),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text ?? standard,
            style: TextStyle(fontSize: 12, height: 1.3, color: pal.subtext),
          ),
        ),
      ],
    );
    if (compact) return row;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: pal.blushSoft,
        borderRadius: BorderRadius.circular(AppDimensions.radiusSmall),
      ),
      child: row,
    );
  }
}

/// A colour that is not known: a neutral dashed circle with its number. A
/// known colour is a filled circle; one that is only an estimate keeps a thin
/// dashed ring, so the eye can tell estimates from facts.
class PanCell extends StatelessWidget {
  const PanCell({
    super.key,
    required this.position,
    this.colour,
    this.approximate = false,
    this.selected = false,
    this.onTap,
    this.size = 40,
    this.label,
  });

  final int position;

  /// Null: the colour is not known (neutral cell).
  final Color? colour;
  final bool approximate;
  final bool selected;
  final VoidCallback? onTap;
  final double size;

  /// Spoken name of the cell (screen readers).
  final String? label;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final known = colour != null;
    final fill = colour ?? pal.field;
    final onFill = known
        ? (fill.computeLuminance() > 0.55
              ? const Color(0xFF3A3135)
              : Colors.white)
        : pal.subtext;
    final cell = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CellPainter(
          fill: fill,
          line: known ? pal.border : pal.subtext.withValues(alpha: 0.55),
          dashed: !known || approximate,
          ring: selected ? pal.accent : null,
        ),
        child: Center(
          child: Text(
            '$position',
            style: TextStyle(
              fontSize: size * 0.32,
              fontWeight: FontWeight.w700,
              color: onFill,
            ),
          ),
        ),
      ),
    );
    final text =
        label ??
        trf('Ячейка {n}', {'n': position}) +
            (known ? '' : ', ${tr('цвет не измерен')}');
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: text,
      child: ExcludeSemantics(
        child: onTap == null
            ? cell
            : InkResponse(
                onTap: onTap,
                radius: size * 0.8,
                containedInkWell: false,
                child: cell,
              ),
      ),
    );
  }
}

class _CellPainter extends CustomPainter {
  _CellPainter({
    required this.fill,
    required this.line,
    required this.dashed,
    required this.ring,
  });

  final Color fill;
  final Color line;
  final bool dashed;
  final Color? ring;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final outer = size.width / 2;
    // the selection ring sits outside the circle
    final r = ring == null ? outer - 1 : outer - 4;
    canvas.drawCircle(c, r, Paint()..color = fill);
    final stroke = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    if (dashed) {
      const dashes = 20;
      final step = 2 * math.pi / dashes;
      for (var i = 0; i < dashes; i++) {
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: r),
          i * step,
          step * 0.55,
          false,
          stroke,
        );
      }
    } else {
      canvas.drawCircle(c, r, stroke);
    }
    if (ring != null) {
      canvas.drawCircle(
        c,
        outer - 1.2,
        Paint()
          ..color = ring!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_CellPainter o) =>
      o.fill != fill || o.line != line || o.dashed != dashed || o.ring != ring;
}

/// The cells of a palette as a tidy grid (five in a row, as many rows as it
/// takes). Cells whose colour is not known are neutral.
class PanGrid extends StatelessWidget {
  const PanGrid({
    super.key,
    required this.pans,
    this.selectedKey,
    this.onSelect,
    this.columns = 5,
  });

  final List<PalettePan> pans;
  final String? selectedKey;

  /// Called for a cell with a known colour (the others cannot be tried on).
  final ValueChanged<PalettePan>? onSelect;
  final int columns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 10.0;
        final cols = math.min(columns, math.max(pans.length, 1));
        final cell = math.min(46.0, (box.maxWidth - gap * (cols - 1)) / cols);
        return ConstrainedBox(
          // exactly `columns` cells in a row, left-aligned
          constraints: BoxConstraints(maxWidth: cols * cell + gap * (cols - 1)),
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final p in pans)
                PanCell(
                  key: Key('pan-${p.key}'),
                  position: p.position,
                  colour: p.colour,
                  approximate: p.isApproximate,
                  selected: p.key == selectedKey,
                  size: cell,
                  onTap: p.canTryOn && onSelect != null
                      ? () => onSelect!(p)
                      : null,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The variants of a line as pills ("00  01  02 ..."): one is chosen, a tap
/// opens another. The full name of a variant is its tooltip and screen-reader
/// label.
class VariantChips extends StatelessWidget {
  const VariantChips({
    super.key,
    required this.variants,
    required this.selectedId,
    required this.onSelect,
  });

  final List<LineVariant> variants;
  final int selectedId;
  final ValueChanged<LineVariant> onSelect;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final v in variants)
          Semantics(
            button: true,
            selected: v.productId == selectedId,
            label: [
              if (v.code != null) v.code!,
              if (v.name != null) v.name!,
            ].join(' '),
            child: Tooltip(
              message: v.name ?? v.code ?? '',
              child: InkWell(
                key: Key('variant-${v.productId}'),
                borderRadius: BorderRadius.circular(20),
                onTap: () => onSelect(v),
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 40,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: v.productId == selectedId
                        ? AppColors.primary
                        : pal.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: v.productId == selectedId
                          ? AppColors.primary
                          : pal.border,
                    ),
                  ),
                  // as wide as its text (at least 48), not as wide as the row
                  child: Center(
                    widthFactor: 1,
                    heightFactor: 1,
                    child: Text(
                      v.code ?? v.name ?? '?',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: v.productId == selectedId
                            ? Colors.white
                            : pal.text,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
