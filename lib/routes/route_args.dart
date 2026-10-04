import 'package:cosmetix/core/beauty/beauty_codes.dart';
import 'package:cosmetix/core/constants/legal_texts.dart';
import 'package:cosmetix/models/beauty_profile.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/models/product_filter.dart';
import 'package:cosmetix/services/color_test_service.dart';

/// Arguments for the catalog screen.
class CatalogArgs {
  const CatalogArgs({
    this.query = '',
    this.category,
    this.zone,
    this.onlySale = false,
  });

  final String query;
  final String? category;
  final String? zone;
  final bool onlySale;
}

class FiltersArgs {
  const FiltersArgs({required this.initial, required this.products});

  final ProductFilter initial;

  /// Products the "found about N items" counter is calculated from.
  final List<Product> products;
}

class LegalArgs {
  const LegalArgs(this.title, this.text);

  final String title;
  final String text;

  static const terms = LegalArgs('Условия использования', LegalTexts.terms);
  static const privacy = LegalArgs(
    'Политика конфиденциальности',
    LegalTexts.privacy,
  );
}

/// Partial results of the colour-type test, passed to the undertone test.
class UndertoneArgs {
  const UndertoneArgs({required this.warm, required this.depth});

  final int warm;
  final int depth;
}

/// Beauty Test, step "about your skin": carries the colour-test result.
class SkinTestArgs {
  const SkinTestArgs({required this.color});

  final ColorTestResult color;
}

/// Beauty Test, optional photo step.
class BeautyPhotoArgs {
  const BeautyPhotoArgs({
    required this.color,
    required this.skinType,
    required this.concerns,
  });

  final ColorTestResult color;
  final SkinType skinType;
  final Set<SkinConcern> concerns;
}

/// What the final Beauty Profile screen shows.
class BeautyResultArgs {
  const BeautyResultArgs({
    required this.profile,
    this.photoUsed = false,
    this.observations = const [],
  });

  final BeautyProfile profile;

  /// True when a valid photo analysis took part.
  final bool photoUsed;
  final List<String> observations;
}
