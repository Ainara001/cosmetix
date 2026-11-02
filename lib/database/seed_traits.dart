/// Demo "who is this product for" data (the AI classifier can add more, see
/// `product_ai_classification`). Keys are `brand|name` of the seeded products.
class ProductTraits {
  const ProductTraits({
    this.skinTypes = const [],
    this.colorTypes = const [],
    this.undertones = const [],
    this.concerns = const [],
    this.tags = const [],
  });

  final List<String> skinTypes;
  final List<String> colorTypes;
  final List<String> undertones;
  final List<String> concerns;
  final List<String> tags;
}

const Map<String, ProductTraits> seedTraits = {
  '3CE|Super Slim Waterproof Mascara': ProductTraits(tags: ['long_wearing']),
  'Rom&nd|Better Than Palette 05 Shade & Shadow Garden': ProductTraits(
    colorTypes: ['autumn', 'spring', 'summer'],
    undertones: ['neutral', 'warm'],
  ),
  'Peripera|Heart Jam Glow Lip': ProductTraits(
    colorTypes: ['spring', 'summer'],
    undertones: ['warm', 'neutral'],
  ),
  'Rom&nd|Better Than Eyes': ProductTraits(
    colorTypes: ['summer', 'winter'],
    undertones: ['cool', 'neutral'],
  ),
  'COSRX|Advanced Snail 96 Mucin Power Essence': ProductTraits(
    skinTypes: ['dry', 'normal', 'combination', 'sensitive'],
    concerns: ['dryness', 'aging'],
    tags: ['hydrating', 'soothing', 'fragrance_free'],
  ),
  'Maison Margiela|Replica Lazy Sunday Morning': ProductTraits(
    tags: ['fragrance'],
  ),
  'Peripera|Ink The Velvet 31 Wine Nude': ProductTraits(
    colorTypes: ['autumn', 'winter'],
    undertones: ['cool', 'neutral'],
    tags: ['long_wearing'],
  ),
  'Peripera|Ink Mood Glowy Tint 30 Happy Berry': ProductTraits(
    colorTypes: ['spring', 'summer'],
    undertones: ['warm', 'neutral'],
    tags: ['long_wearing'],
  ),
  'Rom&nd|Glasting Color Gloss': ProductTraits(
    colorTypes: ['summer', 'spring'],
    undertones: ['neutral', 'cool'],
  ),
  'Missha|Magic Cushion Moist Up': ProductTraits(
    skinTypes: ['normal', 'combination', 'dry'],
    colorTypes: ['spring', 'summer'],
    undertones: ['neutral', 'warm'],
    tags: ['spf'],
  ),
  'Beauty of Joseon|Relief Sun: Rice + Probiotics SPF50+': ProductTraits(
    skinTypes: ['normal', 'combination', 'oily'],
    concerns: ['pigmentation', 'aging'],
    tags: ['spf', 'fragrance_free'],
  ),
  'The Ordinary|Niacinamide 10% + Zinc 1%': ProductTraits(
    skinTypes: ['oily', 'combination', 'normal'],
    concerns: ['acne', 'pigmentation'],
    tags: ['oil_control', 'brightening', 'fragrance_free'],
  ),
  'Rom&nd|Better Than Cheek': ProductTraits(
    colorTypes: ['spring', 'summer', 'autumn'],
    undertones: ['neutral', 'warm'],
  ),
  'CeraVe|Moisturizing Cream': ProductTraits(
    skinTypes: ['dry', 'normal', 'sensitive'],
    concerns: ['dryness'],
    tags: ['hydrating', 'soothing', 'fragrance_free'],
  ),
  'Nivea|Soft Moisturizing Creme': ProductTraits(
    skinTypes: ['normal', 'dry'],
    concerns: ['dryness'],
    tags: ['hydrating'],
  ),
  'Mise-en-scène|Perfect Serum Shampoo': ProductTraits(tags: ['fragrance']),
  'Anua|Heartleaf 77% Soothing Toner': ProductTraits(
    skinTypes: ['oily', 'sensitive', 'combination', 'normal'],
    concerns: ['acne', 'sensitivity'],
    tags: ['soothing', 'fragrance_free'],
  ),
  'The Ordinary|Glycolic Acid 7% Toning Solution': ProductTraits(
    skinTypes: ['normal', 'combination', 'oily'],
    concerns: ['pigmentation', 'aging'],
    tags: ['brightening', 'fragrance_free'],
  ),
  'The Ordinary|Retinol 0.5% in Squalane': ProductTraits(
    skinTypes: ['normal', 'dry', 'combination'],
    concerns: ['aging', 'pigmentation'],
    tags: ['fragrance_free'],
  ),
  'COSRX|BHA Blackhead Power Liquid': ProductTraits(
    skinTypes: ['oily', 'combination'],
    concerns: ['acne'],
    tags: ['oil_control', 'fragrance_free'],
  ),
  'Klairs|Freshly Juiced Vitamin Drop': ProductTraits(
    skinTypes: ['normal', 'dry', 'combination'],
    concerns: ['pigmentation', 'aging'],
    tags: ['brightening'],
  ),
  'Rom&nd|Better Than Palette 00 Light & Glitter Garden': ProductTraits(
    colorTypes: ['summer', 'winter'],
    undertones: ['cool', 'neutral'],
  ),
  'Rom&nd|Better Than Palette 01 Pampas Garden': ProductTraits(
    colorTypes: ['spring', 'autumn'],
    undertones: ['warm', 'neutral'],
  ),
  'Rom&nd|Better Than Palette 02 Mahogany Garden': ProductTraits(
    colorTypes: ['autumn'],
    undertones: ['warm'],
  ),
  'Rom&nd|Better Than Palette 03 Rosebud Garden': ProductTraits(
    colorTypes: ['summer', 'winter'],
    undertones: ['cool', 'neutral'],
  ),
  'Rom&nd|Better Than Palette 07 Berry Fuchsia Garden': ProductTraits(
    colorTypes: ['winter', 'summer'],
    undertones: ['cool'],
  ),
  'Peripera|Ink Mood Glowy Tint 03 Rose In Mind': ProductTraits(
    colorTypes: ['summer', 'spring'],
    undertones: ['cool', 'neutral'],
    tags: ['long_wearing'],
  ),
  'Rom&nd|Juicy Lasting Tint 01 Pomelo Skin': ProductTraits(
    colorTypes: ['spring', 'autumn'],
    undertones: ['warm', 'neutral'],
    tags: ['long_wearing'],
  ),
  '3CE|Mood Recipe Face Blush': ProductTraits(
    colorTypes: ['spring', 'autumn'],
    undertones: ['warm', 'neutral'],
  ),
  'Torriden|Dive-In Serum': ProductTraits(
    skinTypes: ['dry', 'normal', 'combination', 'sensitive'],
    concerns: ['dryness'],
    tags: ['hydrating', 'fragrance_free'],
  ),
  'Skin1004|Madagascar Centella Ampoule': ProductTraits(
    skinTypes: ['sensitive', 'oily', 'combination', 'normal'],
    concerns: ['sensitivity', 'acne'],
    tags: ['soothing', 'fragrance_free'],
  ),
  'Beauty of Joseon|Glow Serum: Propolis + Niacinamide': ProductTraits(
    skinTypes: ['oily', 'combination', 'normal'],
    concerns: ['acne', 'pigmentation'],
    tags: ['brightening', 'fragrance_free'],
  ),
  'Isntree|Hyaluronic Acid Toner': ProductTraits(
    skinTypes: ['dry', 'normal', 'combination', 'sensitive'],
    concerns: ['dryness'],
    tags: ['hydrating', 'fragrance_free'],
  ),
  'Round Lab|1025 Dokdo Toner': ProductTraits(
    skinTypes: ['sensitive', 'normal', 'combination', 'oily'],
    concerns: ['sensitivity'],
    tags: ['soothing', 'fragrance_free'],
  ),
  'Laneige|Lip Sleeping Mask': ProductTraits(
    skinTypes: ['dry', 'normal'],
    concerns: ['dryness'],
    tags: ['hydrating'],
  ),
  'COSRX|Low pH Good Morning Gel Cleanser': ProductTraits(
    skinTypes: ['oily', 'combination', 'sensitive', 'normal'],
    concerns: ['acne'],
    tags: ['oil_control'],
  ),
  'Dr.Jart+|Ceramidin Cream': ProductTraits(
    skinTypes: ['dry', 'sensitive', 'normal'],
    concerns: ['dryness', 'sensitivity'],
    tags: ['hydrating', 'soothing'],
  ),
};
