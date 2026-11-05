import '../domain/makeup_look.dart';

/// The numbers of the pigment engine. They are DESIGN PARAMETERS, not
/// measurements: how much of its colour a typical lipstick, eyeshadow or blush
/// shows at normal application (lipsticks and matte shadows cover well, a blush
/// is sheer). Nothing measured exists yet; when a shade has a measured opacity
/// it overrides these (see `ZoneLook.opacity`).
class PigmentParams {
  const PigmentParams({
    this.lipsOpacity = 0.9,
    this.eyeshadowOpacity = 0.9,
    this.blushOpacity = 0.6,
    this.minGain = 0.02,
    this.maxGain = 8.0,
    this.gateStart = 2.5,
    this.gateEnd = 4.5,
    this.lightnessWeight = 0.35,
    this.gateSoftness = 0.0,
    this.textureMin = 0.5,
    this.textureMax = 1.3,
    this.darkStart = 0.08,
    this.darkEnd = 0.35,
    this.highlightStart = 1.5,
    this.highlightEnd = 2.5,
    this.highlightKeep = 1.0,
    this.paleStart = 0.2,
    this.paleEnd = 0.6,
    this.lipsColourTexture = 0.6,
    this.chromaReliableStart = 8,
    this.chromaReliableEnd = 28,
    this.lipsChromaFloor = 3.5,
    this.skinChromaFloor = 6.0,
  });

  final double lipsOpacity;
  final double eyeshadowOpacity;
  final double blushOpacity;

  /// Limits of the colour gain of a zone (a very dark zone must not turn into
  /// amplified noise).
  final double minGain;
  final double maxGain;

  /// A pixel whose colour is [gateStart] "typical spreads" away from the colour
  /// of its zone gets paint fading out; at [gateEnd] it gets none (a finger, a
  /// nail, teeth, hair, the frame of glasses).
  final double gateStart;
  final double gateEnd;

  /// How much a difference in lightness counts compared with a difference in
  /// colour when deciding that a pixel does not belong to the zone (small: a
  /// shadow or a highlight on the lips is still the lips).
  final double lightnessWeight;

  /// How far the edge of the gate is spread, as a share of the face width: the
  /// gate decides pixel by pixel, and an abrupt decision between neighbours would
  /// show as a seam in the texture.
  final double gateSoftness;

  /// How the contrast of the LIGHTNESS texture follows a change of lightness of
  /// the zone: the exponent is the old lightness over the new one, kept between
  /// these limits. A zone that gets much lighter would otherwise show its texture
  /// amplified (a relative contrast kept in a brighter picture reads as stronger).
  /// The texture of the COLOUR (redness, spots) is always kept in full.
  final double textureMin;
  final double textureMax;

  /// Pixels much darker than their zone (the line between the lips, a shadow in
  /// the mouth) keep their own hue: from [darkStart] to [darkEnd] (as a share of
  /// the zone's luminance) the colour gain turns from one common value into the
  /// per-channel one.
  final double darkStart;
  final double darkEnd;

  /// How much of the variation of COLOUR between the pixels of the lips is kept
  /// (1 = all). The lips differ strongly in colour from body to rim to line, and
  /// a full-strength copy of that difference over a very different product colour
  /// would exaggerate it (a crimson rim turning violet). The skin zones (blush,
  /// eyeshadow) keep it in full: that is where redness, spots and scars live.
  final double lipsColourTexture;

  /// The colour of a very dark pixel is mostly noise: below [chromaReliableStart]
  /// (L*) the gate ignores a pixel's colour and judges it by lightness alone, and
  /// it counts in full from [chromaReliableEnd].
  final double chromaReliableStart;
  final double chromaReliableEnd;

  /// The smallest typical spread of colour (a*, b*) the gate assumes. On skin
  /// zones it is larger: a red spot, a freckle or a mole is still skin and must
  /// take the makeup (and show through it); only a colour far beyond that (hair,
  /// a frame, a finger) is rejected.
  final double lipsChromaFloor;
  final double skinChromaFloor;

  double chromaFloorOf(MakeupZone zone) =>
      zone == MakeupZone.lips ? lipsChromaFloor : skinChromaFloor;

  double colourTextureOf(MakeupZone zone) =>
      zone == MakeupZone.lips ? lipsColourTexture : 1.0;

  /// Pixels much paler than the zone's typical colour (the rim of the lips, where
  /// they blend into the skin; a reflection): from [paleStart] to [paleEnd] times
  /// the zone's typical saturation the pixel turns from taking only the change of
  /// lightness to taking the change of colour too. A pale pixel with a full
  /// per-channel gain would take an odd tint.
  final double paleStart;
  final double paleEnd;

  /// Highlights (gloss, a reflection, a wet shine): a pixel that is much lighter
  /// than its zone (from [highlightStart] to [highlightEnd] times its luminance)
  /// AND nearly colourless is a highlight; up to [highlightKeep] of the paint is
  /// withdrawn there, so a highlight stays white instead of taking a tint.
  final double highlightStart;
  final double highlightEnd;
  final double highlightKeep;

  double opacityOf(MakeupZone zone) => switch (zone) {
    MakeupZone.lips => lipsOpacity,
    MakeupZone.eyeshadow => eyeshadowOpacity,
    MakeupZone.blush => blushOpacity,
  };

  static const standard = PigmentParams();
}
