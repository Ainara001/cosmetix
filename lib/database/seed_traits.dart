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
  'Flower Knows|Палетка Flower Knows Strawberry': ProductTraits(
    colorTypes: ['spring', 'summer'],
    undertones: ['cool', 'neutral'],
    tags: ['long_wearing'],
  ),
  'Peripera|Палетка Peripera Ink Cozy': ProductTraits(
    colorTypes: ['autumn', 'spring'],
    undertones: ['warm', 'neutral'],
  ),
  'Flower Knows|Strawberry Lip Tint': ProductTraits(
    colorTypes: ['summer', 'winter'],
    undertones: ['cool', 'neutral'],
    tags: ['long_wearing'],
  ),
  'Rom&nd|Better Than Eyes': ProductTraits(
    colorTypes: ['autumn', 'spring', 'summer'],
    undertones: ['neutral', 'warm'],
  ),
  'Rom&nd|Сыворотка для лица': ProductTraits(
    skinTypes: ['dry', 'normal', 'combination'],
    concerns: ['dryness', 'aging'],
    tags: ['hydrating'],
  ),
  'Peripera|Парфюм Peripera Mood': ProductTraits(tags: ['fragrance']),
  'Flower Knows|Тинт для губ Flower Knows': ProductTraits(
    colorTypes: ['winter', 'summer'],
    undertones: ['cool'],
    tags: ['long_wearing'],
  ),
  'Peripera|Тинт Peripera Ink': ProductTraits(
    colorTypes: ['spring', 'autumn'],
    undertones: ['warm'],
    tags: ['long_wearing'],
  ),
  'Rom&nd|Блеск Rom&nd Glasting': ProductTraits(
    colorTypes: ['summer', 'spring'],
    undertones: ['neutral', 'cool'],
  ),
  'Missha|Кушон Missha Magic': ProductTraits(
    skinTypes: ['normal', 'combination', 'dry'],
    colorTypes: ['spring', 'summer'],
    undertones: ['neutral', 'warm'],
    tags: ['spf'],
  ),
  'Beauty of Joseon|Крем SPF 50 Relief Sun': ProductTraits(
    skinTypes: ['normal', 'combination', 'oily'],
    concerns: ['pigmentation', 'aging'],
    tags: ['spf', 'fragrance_free'],
  ),
  'The Ordinary|Сыворотка Niacinamide 10%': ProductTraits(
    skinTypes: ['oily', 'combination', 'normal'],
    concerns: ['acne', 'pigmentation'],
    tags: ['oil_control', 'brightening'],
  ),
  'Rom&nd|Румяна Better Than Cheek': ProductTraits(
    colorTypes: ['spring', 'summer', 'autumn'],
    undertones: ['neutral', 'warm'],
  ),
  'Dr.Jart+|Увлажняющий крем для тела': ProductTraits(
    skinTypes: ['dry', 'normal'],
    concerns: ['dryness'],
    tags: ['hydrating', 'soothing'],
  ),
  'Cosmetics Mockup|Cosmetics Mockup Cream': ProductTraits(
    skinTypes: ['normal', 'dry'],
    concerns: ['dryness'],
    tags: ['hydrating'],
  ),
  'Anua|Тонер Heartleaf 77%': ProductTraits(
    skinTypes: ['oily', 'sensitive', 'combination', 'normal'],
    concerns: ['acne', 'sensitivity'],
    tags: ['soothing', 'fragrance_free'],
  ),
};
