import 'dart:convert';

import 'package:cosmetix/database/catalog_data.dart';

/// How sure the normalizer is about a store category.
enum CategoryDecision {
  /// The dictionary names exactly one type.
  matched,

  /// A person already decided this wording in the review queue.
  alias,

  /// Two or more types fit equally well ("крем-гель"): a person decides.
  ambiguous,

  /// No word of the dictionary is in the text: a person decides.
  unknown,
}

class NormalizedCategory {
  const NormalizedCategory({
    required this.raw,
    required this.key,
    required this.decision,
    this.typeKey,
    this.typeName,
    this.candidates = const [],
  });

  /// The text as the shop wrote it.
  final String raw;

  /// Stems of the meaningful words, sorted: the same for "увлажняющий крем"
  /// and "крем увлажняющий". Identifies the wording in the review queue.
  final String key;
  final CategoryDecision decision;

  /// The unified category (`cream`) and its name ("Крем"); null when a person
  /// must decide.
  final String? typeKey;
  final String? typeName;

  /// Type keys that fit when [decision] is ambiguous.
  final List<String> candidates;

  bool get needsReview =>
      decision == CategoryDecision.ambiguous ||
      decision == CategoryDecision.unknown;
}

class CategoryType {
  const CategoryType(this.key, this.name);
  final String key;
  final String name;
}

/// Turns the many ways shops write a category into one product type.
///
/// Words are compared as a set, without order and without word endings:
/// "увлажняющий крем", "крем увлажняющий" and "Кремы увлажняющие" all give
/// the same set and land in "Крем". The dictionary
/// (`assets/catalog/category_dictionary.json`) knows the type words and a few
/// phrases that must win over a single word ("тональный крем" is a
/// foundation, not a cream). When the text does not decide one type it is
/// never guessed: the result says `ambiguous` or `unknown` and the caller puts
/// it into the manual review queue.
class CategoryNormalizer {
  CategoryNormalizer._(
    this.types,
    this._ignore,
    this._wordTypes,
    this._phrases,
    this._aliases,
  );

  /// All unified categories by key.
  final Map<String, CategoryType> types;
  final Set<String> _ignore;
  final Map<String, Set<String>> _wordTypes; // stem -> type keys
  final List<({Set<String> stems, String type})> _phrases;
  final Map<String, String> _aliases;

  factory CategoryNormalizer.fromJson(
    String json, {
    Map<String, String> aliases = const {},
  }) {
    final j = jsonDecode(json) as Map<String, Object?>;
    final ignore = {
      for (final w in j['ignore'] as List) stem((w as String).toLowerCase()),
    };
    final types = <String, CategoryType>{};
    final wordTypes = <String, Set<String>>{};
    for (final t in (j['types'] as List).cast<Map<String, Object?>>()) {
      final key = t['key'] as String;
      types[key] = CategoryType(key, t['name'] as String);
      for (final w in (t['words'] as List).cast<String>()) {
        wordTypes.putIfAbsent(stem(w), () => {}).add(key);
      }
    }
    final phrases = <({Set<String> stems, String type})>[];
    for (final p in (j['phrases'] as List).cast<Map<String, Object?>>()) {
      final type = p['type'] as String;
      if (!types.containsKey(type)) {
        throw FormatException('category dictionary: unknown type "$type"');
      }
      final stems = {
        for (final w in (p['words'] as List).cast<String>()) stem(w),
      }..removeAll(ignore);
      if (stems.isNotEmpty) phrases.add((stems: stems, type: type));
    }
    for (final target in aliases.values) {
      if (!types.containsKey(target)) {
        throw FormatException('category alias to unknown type "$target"');
      }
    }
    return CategoryNormalizer._(types, ignore, wordTypes, phrases, aliases);
  }

  /// Reads the bundled dictionary. [aliases] are the wordings people already
  /// resolved in the review queue (`normalized key -> type key`).
  static Future<CategoryNormalizer> load({
    Map<String, String> aliases = const {},
  }) async => CategoryNormalizer.fromJson(
    await CatalogData.assetReader(dictionaryAsset),
    aliases: aliases,
  );

  static const dictionaryAsset = 'assets/catalog/category_dictionary.json';

  /// Words of [text]: lower case, "ё" as "е", split on everything that is not
  /// a letter or a digit (so "крем-гель" are two words), numbers dropped.
  static List<String> words(String text) {
    final lower = text.toLowerCase().replaceAll('ё', 'е');
    return [
      for (final m in RegExp(r'[a-zа-я]+').allMatches(lower))
        if (m.group(0)!.length >= 2) m.group(0)!,
    ];
  }

  static const _ruEndings = [
    // longest first
    'ого', 'его', 'ому', 'ему', 'ыми', 'ими', 'ами', 'ями', 'ием', 'ией',
    'ая', 'яя', 'ое', 'ее', 'ые', 'ие', 'ых', 'их', 'ый', 'ий', 'ой', 'ую',
    'юю', 'ым', 'им', 'ом', 'ем', 'ей', 'ов', 'ев', 'ах', 'ях', 'ия', 'ии',
    'ию', 'ь', 'ы', 'и', 'а', 'я', 'у', 'ю', 'е', 'о',
  ];

  /// A light stemmer: it removes one common ending (Russian) or a plural
  /// "s" (English), never leaving fewer than 3 letters. Both the dictionary
  /// and the shop text go through it, so the endings cancel out.
  static String stem(String word) {
    final w = word.toLowerCase().replaceAll('ё', 'е');
    if (RegExp(r'^[a-z]+$').hasMatch(w)) {
      if (w.length > 4 && w.endsWith('ches')) {
        return w.substring(0, w.length - 2);
      }
      if (w.length > 3 && w.endsWith('s') && !w.endsWith('ss')) {
        return w.substring(0, w.length - 1);
      }
      return w;
    }
    for (final e in _ruEndings) {
      if (w.endsWith(e) && w.length - e.length >= 3) {
        return w.substring(0, w.length - e.length);
      }
    }
    return w;
  }

  NormalizedCategory normalize(String raw) {
    final stems = {for (final w in words(raw)) stem(w)};
    final meaningful = stems.difference(_ignore);
    final key = (meaningful.toList()..sort()).join(' ');

    NormalizedCategory done(
      CategoryDecision d, [
      String? type,
      List<String> candidates = const [],
    ]) => NormalizedCategory(
      raw: raw,
      key: key,
      decision: d,
      typeKey: type,
      typeName: type == null ? null : types[type]!.name,
      candidates: candidates,
    );

    final alias = _aliases[key];
    if (alias != null) return done(CategoryDecision.alias, alias);

    // type -> how many words of the text decide it; the most specific wins
    final score = <String, int>{};
    void hit(String type, int n) {
      if ((score[type] ?? 0) < n) score[type] = n;
    }

    for (final s in meaningful) {
      for (final t in _wordTypes[s] ?? const <String>{}) {
        hit(t, 1);
      }
    }
    for (final p in _phrases) {
      if (p.stems.every(meaningful.contains)) hit(p.type, p.stems.length);
    }
    if (score.isEmpty) return done(CategoryDecision.unknown);
    final best = score.values.reduce((a, b) => a > b ? a : b);
    final top = [
      for (final e in score.entries)
        if (e.value == best) e.key,
    ]..sort();
    if (top.length == 1) return done(CategoryDecision.matched, top.single);
    return done(CategoryDecision.ambiguous, null, top);
  }
}
