import 'dart:ui' show Color;

/// The three zones of stage 1. A zone is the area of the face a product goes on.
enum MakeupZone { lips, eyeshadow, blush }

/// What the user chose for one zone.
class ZoneLook {
  const ZoneLook({
    required this.color,
    this.intensity = 0.6,
    this.enabled = true,
  });

  final Color color;

  /// 0 = nothing is applied, 1 = the strongest this module applies.
  final double intensity;
  final bool enabled;

  /// True when this zone changes the photo at all.
  bool get active => enabled && intensity > 0;

  ZoneLook copyWith({Color? color, double? intensity, bool? enabled}) =>
      ZoneLook(
        color: color ?? this.color,
        intensity: intensity ?? this.intensity,
        enabled: enabled ?? this.enabled,
      );
}

/// A complete virtual look: one [ZoneLook] per zone.
class MakeupLook {
  const MakeupLook({
    this.lips = const ZoneLook(color: Color(0xFFB03A48)),
    this.eyeshadow = const ZoneLook(color: Color(0xFF8A6A7A), intensity: 0.5),
    this.blush = const ZoneLook(color: Color(0xFFE08A8A), intensity: 0.5),
  });

  final ZoneLook lips;
  final ZoneLook eyeshadow;
  final ZoneLook blush;

  ZoneLook of(MakeupZone zone) => switch (zone) {
    MakeupZone.lips => lips,
    MakeupZone.eyeshadow => eyeshadow,
    MakeupZone.blush => blush,
  };

  MakeupLook with_(MakeupZone zone, ZoneLook value) => switch (zone) {
    MakeupZone.lips => MakeupLook(
      lips: value,
      eyeshadow: eyeshadow,
      blush: blush,
    ),
    MakeupZone.eyeshadow => MakeupLook(
      lips: lips,
      eyeshadow: value,
      blush: blush,
    ),
    MakeupZone.blush => MakeupLook(
      lips: lips,
      eyeshadow: eyeshadow,
      blush: value,
    ),
  };

  /// No zone changes the photo.
  bool get isEmpty => !lips.active && !eyeshadow.active && !blush.active;
}
