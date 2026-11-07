import 'package:flutter/material.dart';

import 'package:cosmetix/core/theme/app_colors.dart';

/// One choice of [PillSegments].
class PillSegment<T> {
  const PillSegment({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// "One of a few" choice in the style of the app's pill chips: a soft rounded
/// track with the chosen segment filled in the brand colour. Replaces the stock
/// segmented button (which has square-ish corners and a tick) on the try-on and
/// other screens, and follows the light and the dark theme.
class PillSegments<T> extends StatelessWidget {
  const PillSegments({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<PillSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: pal.field,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        children: [
          for (final s in segments)
            Expanded(
              child: Semantics(
                button: true,
                selected: s.value == selected,
                label: s.label,
                child: ExcludeSemantics(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => onChanged(s.value),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      constraints: const BoxConstraints(minHeight: 44),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: s.value == selected
                            ? AppColors.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (s.icon != null) ...[
                            Icon(
                              s.icon,
                              size: 18,
                              color: s.value == selected
                                  ? Colors.white
                                  : pal.subtext,
                            ),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              s.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: s.value == selected
                                    ? Colors.white
                                    : pal.text,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
