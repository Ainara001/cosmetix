import 'package:cosmetix/models/safety_models.dart';

/// One ingredient of the scanned list that hits an item of the user's
/// blacklist.
class ScanMatch {
  const ScanMatch({
    required this.ingredient,
    required this.item,
    required this.reason,
  });

  /// The ingredient as it was read / typed.
  final String ingredient;
  final BlacklistItem item;

  /// What matched: the group the ingredient belongs to, or the typed word.
  final ScanMatchReason reason;
}

enum ScanMatchReason {
  /// The name belongs to a known group (parabens, sulfates ...).
  group,

  /// The name contains a component the user added themselves.
  custom,
}

/// Compares a list of ingredient names with the user's blacklist. Only items
/// the user switched on count. Group matching is by well-known INCI / Russian
/// names; it can miss rare names, so a clean result is never a guarantee.
class IngredientMatcher {
  IngredientMatcher._();

  /// group key -> patterns of the names that belong to the group.
  static final Map<String, List<RegExp>> _groups = {
    'paraben': [RegExp(r'paraben'), RegExp(r'парабен')],
    'sulfate': [
      RegExp(
        r'\b(sodium|ammonium|magnesium|tea|mea|potassium)\s+'
        r'(lauryl|laureth|myreth|coco|cocoyl|c12-?15 pareth)\s*(\d+\s*)?sulfate',
      ),
      RegExp(r'\bsl(e)?s\b'),
      RegExp(r'лаурил\s*сульфат|лаурет\s*сульфат|лауретсульфат|лаурилсульфат'),
    ],
    'silicone': [
      RegExp(r'\w*methicone\b'),
      RegExp(r'dimethiconol'),
      RegExp(r'siloxane'),
      RegExp(r'silicone'),
      RegExp(r'диметикон|циклометикон|силоксан|силикон|триметикон'),
    ],
    'mineral_oil': [
      RegExp(r'mineral oil'),
      RegExp(r'paraffinum liquidum'),
      RegExp(r'\bpetrolatum\b'),
      RegExp(r'\bparaffin\b'),
      RegExp(r'petroleum jelly'),
      RegExp(r'\bceresin\b'),
      RegExp(r'минеральное масло|вазелин|парафин'),
    ],
    'formaldehyde': [
      RegExp(r'formaldehyde'),
      RegExp(r'formalin'),
      RegExp(r'dmdm hydantoin'),
      RegExp(r'quaternium-15'),
      RegExp(r'(imidazolidinyl|diazolidinyl) urea'),
      RegExp(r'bronopol'),
      RegExp(r'формальдегид|формалин'),
    ],
    'phthalates': [
      RegExp(r'phthalate'),
      RegExp(r'\b(dbp|dep|dehp)\b'),
      RegExp(r'фталат'),
    ],
    'triclosan': [RegExp(r'triclosan'), RegExp(r'триклозан')],
  };

  /// Lower case, "ё" -> "е", no accents, single spaces.
  static String normalize(String s) => s
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[éèê]'), 'e')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// True when [ingredient] belongs to the blacklist group [groupKey].
  static bool inGroup(String ingredient, String groupKey) {
    final n = normalize(ingredient);
    return (_groups[groupKey] ?? const []).any((re) => re.hasMatch(n));
  }

  static List<ScanMatch> match(
    List<String> ingredients,
    List<BlacklistItem> blacklist,
  ) {
    final out = <ScanMatch>[];
    for (final item in blacklist.where((b) => b.enabled)) {
      for (final ing in ingredients) {
        if (item.groupKey != null && inGroup(ing, item.groupKey!)) {
          out.add(
            ScanMatch(
              ingredient: ing,
              item: item,
              reason: ScanMatchReason.group,
            ),
          );
        } else if (item.isCustom &&
            item.name.trim().length >= 2 &&
            normalize(ing).contains(normalize(item.name))) {
          out.add(
            ScanMatch(
              ingredient: ing,
              item: item,
              reason: ScanMatchReason.custom,
            ),
          );
        }
      }
    }
    return out;
  }
}
