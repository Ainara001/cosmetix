/// Turns the text found on a package (OCR output or typed by the user) into a
/// clean list of ingredient names. Pure logic, no UI, no I/O.
class IngredientTextParser {
  IngredientTextParser._();

  /// Words that start the ingredient list on a package.
  static final _start = RegExp(
    r'(ingredients?|ingr[eé]dients?|ingredientes|inci|composition|'
    r'состав|ингредиенты)\s*[:\-–—]?',
    caseSensitive: false,
  );

  /// Words after which the ingredient list is over.
  static final _stop = RegExp(
    r'(?<!\p{L})(warning|caution|directions?|how to use|may contain|made in|'
    r'best before|batch|storage|manufactured|distributed|www\.|'
    r'применение|способ применения|срок годности|хранить|хранение|'
    r'производитель|изготовитель|предупреждение|меры предосторожности)'
    r'(?!\p{L})',
    caseSensitive: false,
    unicode: true,
  );

  static const maxItemLength = 80;
  static const maxItems = 150;

  /// Ingredient names in the order they appear, without duplicates.
  static List<String> parse(String raw) {
    var text = raw.replaceAll('\r', '\n');
    // "methyl-\nparaben" was one word that the label broke across two lines
    text = text.replaceAllMapped(RegExp(r'(\w)-\n(?=\w)'), (m) => m.group(1)!);
    text = _afterStartMarker(text);
    text = _beforeStopMarker(text);

    final hasSeparators = RegExp(r'[,;•·|]').hasMatch(text);
    final parts = hasSeparators
        ? _split(text.replaceAll('\n', ' '))
        // one ingredient per line (a typed or scanned list without commas)
        : text.split('\n');

    final seen = <String>{};
    final out = <String>[];
    for (final p in parts) {
      final name = _clean(p);
      if (name == null) continue;
      if (seen.add(name.toLowerCase())) out.add(name);
      if (out.length >= maxItems) break;
    }
    return out;
  }

  /// Comma separated text for the editable field.
  static String join(List<String> items) => items.join(', ');

  static String _afterStartMarker(String text) {
    final m = _start.firstMatch(text);
    return m == null ? text : text.substring(m.end);
  }

  static String _beforeStopMarker(String text) {
    final m = _stop.firstMatch(text);
    return m == null ? text : text.substring(0, m.start);
  }

  /// Splits on , ; • · | but not inside brackets: "Aqua (Water, Eau)".
  static List<String> _split(String text) {
    final parts = <String>[];
    final buf = StringBuffer();
    var depth = 0;
    for (final ch in text.split('')) {
      if (ch == '(' || ch == '[') depth++;
      if ((ch == ')' || ch == ']') && depth > 0) depth--;
      final isSep = depth == 0 && (',;•·|'.contains(ch));
      if (isSep) {
        parts.add(buf.toString());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    parts.add(buf.toString());
    return parts;
  }

  static String? _clean(String s) {
    var t = s
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[\s\-–—*•·.:;]+'), '')
        .replaceAll(RegExp(r'[\s\-–—*•·.:;]+$'), '')
        .trim();
    // a leading "and" / "и" from "…, and Fragrance"
    t = t.replaceFirst(RegExp(r'^(and|и)\s+', caseSensitive: false), '');
    if (t.length < 2 || t.length > maxItemLength) return null;
    if (!RegExp(r'[A-Za-zА-Яа-яЁё]').hasMatch(t)) return null; // numbers only
    return t;
  }
}
