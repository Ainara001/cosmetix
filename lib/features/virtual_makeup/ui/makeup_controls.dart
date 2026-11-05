import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/custom_button.dart';
import 'package:flutter/material.dart';

import '../domain/makeup_look.dart';
import 'makeup_palettes.dart';

/// One zone: on/off, colour and intensity.
class ZoneControl extends StatelessWidget {
  const ZoneControl({
    super.key,
    required this.zone,
    required this.look,
    required this.onChanged,
  });

  final MakeupZone zone;
  final ZoneLook look;
  final ValueChanged<ZoneLook> onChanged;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final swatches = MakeupPalettes.of(zone);
    final name = tr(MakeupPalettes.zoneName(zone));
    return AppCard(
      key: Key('vm-zone-${zone.name}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(name, style: AppTextStyles.bodyBold)),
              Switch(
                key: Key('vm-switch-${zone.name}'),
                value: look.enabled,
                onChanged: (v) => onChanged(look.copyWith(enabled: v)),
              ),
            ],
          ),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: look.enabled ? 1 : 0.4,
            child: IgnorePointer(
              ignoring: !look.enabled,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final s in swatches)
                          _Dot(
                            key: Key('vm-swatch-${zone.name}-${s.name}'),
                            color: s.color,
                            label: tr(s.name),
                            selected:
                                look.color.toARGB32() == s.color.toARGB32(),
                            onTap: () =>
                                onChanged(look.copyWith(color: s.color)),
                          ),
                        _CustomDot(
                          zone: zone,
                          color: look.color,
                          selected: !swatches.any(
                            (s) => s.color.toARGB32() == look.color.toARGB32(),
                          ),
                          onPicked: (c) => onChanged(look.copyWith(color: c)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    trf('Интенсивность: {v0}%', {
                      'v0': (look.intensity * 100).round(),
                    }),
                    style: AppTextStyles.small.copyWith(color: pal.subtext),
                  ),
                  Slider(
                    key: Key('vm-slider-${zone.name}'),
                    value: look.intensity,
                    onChanged: (v) => onChanged(look.copyWith(intensity: v)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({
    super.key,
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Semantics(
      label: label,
      button: true,
      selected: selected,
      child: InkResponse(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? pal.accent : pal.border,
                width: selected ? 3 : 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomDot extends StatelessWidget {
  const _CustomDot({
    required this.zone,
    required this.color,
    required this.selected,
    required this.onPicked,
  });

  final MakeupZone zone;
  final Color color;
  final bool selected;
  final ValueChanged<Color> onPicked;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Semantics(
      label: tr('Свой цвет'),
      button: true,
      child: InkResponse(
        key: Key('vm-custom-${zone.name}'),
        onTap: () async {
          final picked = await showModalBottomSheet<Color>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => _ColorSheet(initial: color),
          );
          if (picked != null) onPicked(picked);
        },
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? pal.accent : pal.border,
              width: selected ? 3 : 1,
            ),
            gradient: const SweepGradient(
              colors: [
                Colors.red,
                Colors.yellow,
                Colors.green,
                Colors.cyan,
                Colors.blue,
                Colors.purple,
                Colors.red,
              ],
            ),
          ),
          child: const Icon(Icons.colorize, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

/// A colour by hue, saturation and lightness.
class _ColorSheet extends StatefulWidget {
  const _ColorSheet({required this.initial});
  final Color initial;

  @override
  State<_ColorSheet> createState() => _ColorSheetState();
}

class _ColorSheetState extends State<_ColorSheet> {
  late HSLColor _hsl = HSLColor.fromColor(widget.initial);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: _hsl.toColor(),
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          const SizedBox(height: 8),
          _row(tr('Оттенок'), _hsl.hue, 360, (v) => _hsl = _hsl.withHue(v)),
          _row(
            tr('Насыщенность'),
            _hsl.saturation,
            1,
            (v) => _hsl = _hsl.withSaturation(v),
          ),
          _row(
            tr('Яркость'),
            _hsl.lightness,
            1,
            (v) => _hsl = _hsl.withLightness(v),
          ),
          const SizedBox(height: 8),
          CustomButton(
            onPressed: () => Navigator.pop(context, _hsl.toColor()),
            label: tr('Готово'),
          ),
        ],
      ),
    );
  }

  Widget _row(
    String label,
    double value,
    double max,
    void Function(double) set,
  ) {
    return Row(
      children: [
        SizedBox(width: 110, child: Text(label, style: AppTextStyles.small)),
        Expanded(
          child: Slider(
            value: value.clamp(0, max),
            max: max,
            onChanged: (v) => setState(() => set(v)),
          ),
        ),
      ],
    );
  }
}
