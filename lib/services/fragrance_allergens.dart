import 'package:cosmetix/services/fragrance_allergen_names.dart';

/// Substances that the EU makes labelling-mandatory in the ingredient list
/// (Annex III of Regulation (EC) 1223/2009, the "fragrance allergens"). The
/// list comes from the official text (see `data/fragrance_allergens.json`); the
/// app only compares names. A product WITHOUT a match is not proof that it is
/// free of allergens: the published list can differ from the real formula.
class FragranceAllergens {
  FragranceAllergens._();

  static final Set<String> _names = fragranceAllergenNames.toSet();

  /// The token of an INCI list without its bracket part: "Citrus Limon
  /// (Lemon) Peel Oil" is "citrus limon peel oil".
  static String normalize(String token) => token
      .toLowerCase()
      .replaceAll(RegExp(r'\([^)]*\)'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static bool isAllergen(String token) => _names.contains(normalize(token));

  /// The ingredients of [inci] that are on the list, as the product names
  /// them, without repeats.
  static List<String> inProduct(String inci) {
    final seen = <String>{};
    return [
      for (final raw in inci.split(RegExp(r'\s*,\s*')))
        if (raw.trim().isNotEmpty &&
            isAllergen(raw) &&
            seen.add(normalize(raw)))
          raw.trim(),
    ];
  }

  /// A regular expression for the composition filter (tested against one
  /// ingredient at a time, brackets removed by [IngredientCatalog.detect]).
  static RegExp get pattern => RegExp(
    '^(${_names.map(RegExp.escape).join('|')})\$',
    caseSensitive: false,
  );
}
