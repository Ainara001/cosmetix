import 'package:flutter/foundation.dart';

import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/utils/formatters.dart';
import 'package:cosmetix/core/beauty/color_palettes.dart';
import 'package:cosmetix/models/beauty_profile.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/models/recommendation.dart';
import 'package:cosmetix/models/social_models.dart';
import 'package:cosmetix/services/ai/ai_client.dart';
import 'package:cosmetix/services/ingredient_analyzer.dart';
import 'package:cosmetix/services/ingredient_catalog.dart';
import 'package:cosmetix/services/recommendation_service.dart';

/// What the assistant knows about shops: the nearest ones and, for the
/// products in question, the price and stock in every shop. Addresses are real,
/// prices and stock are demo values (the prompt says so).
class StoreContext {
  const StoreContext({
    required this.located,
    required this.nearest,
    required this.offers,
  });

  /// True when the distances are counted from the user's real position.
  final bool located;
  final List<StoreInfo> nearest;

  /// product id -> offers, nearest shop first.
  final Map<int, List<StorePrice>> offers;
}

typedef StoreContextLoader =
    Future<StoreContext> Function(List<int> productIds);

/// The chat assistant: an AI model (through the Cosmetix AI proxy) that knows the
/// catalog and, only when the user agreed (`shareProfile`), their Beauty
/// Profile and blacklist, plus the product being discussed.
/// Throws [AiException] when the server is not available: the caller shows a
/// friendly message, nothing else in the app depends on the chat.
class AssistantService {
  AssistantService(this._reco, this._client, {StoreContextLoader? stores})
    // ignore: prefer_initializing_formals
    : _stores = stores;

  final RecommendationService _reco;
  final AiClient _client;
  final StoreContextLoader? _stores;

  /// How many previous messages are sent as conversation context.
  static const historyLimit = 8;

  /// Longest answer we ask for (cost control; the proxy caps it as well).
  static const maxAnswerTokens = 400;

  /// At most this many catalog lines go into the prompt.
  static const maxCatalogLines = 60;

  /// Added to the answer when the user describes a serious reaction, whatever
  /// the model says.
  static String get safetyNote => tr(
    'Если реакция сильная (отёк, затруднённое дыхание, сильная сыпь, боль) — прекратите использовать средство и обратитесь к врачу.',
  );

  static final _serious = RegExp(
    r'отёк|отек|задых|затрудн\w* дыхан|анафилакс|сильн\w* (сыпь|ожог|зуд|покраснен)|'
    r'swell|breath|hives|anaphyla|severe (rash|burn|itch|reaction)|'
    r'ісін|тыныс',
    caseSensitive: false,
  );

  static bool isSeriousReaction(String text) => _serious.hasMatch(text);

  Future<String> reply({
    required int userId,
    required String text,
    required List<ChatMessage> history,
    int? productId,
    bool shareProfile = false,
  }) async {
    final ctx = await _reco.loadContext(userId);
    StoreContext? shops;
    try {
      final focus = _focusProducts(ctx, text, productId, shareProfile);
      shops = await _stores?.call([for (final c in focus) c.product.id]);
    } catch (_) {
      shops = null; // the answer works without shop data
    }
    final system = buildSystemPrompt(
      ctx: ctx,
      question: text,
      productId: productId,
      language: currentLang.englishName,
      shareProfile: shareProfile,
      stores: shops,
    );
    final recent = history.length > historyLimit
        ? history.sublist(history.length - historyLimit)
        : history;
    final reply = await _client.chat(
      temperature: 0.4,
      maxTokens: maxAnswerTokens,
      messages: [
        AiMessage('system', system),
        for (final m in recent)
          AiMessage(m.isUser ? 'user' : 'assistant', m.text),
        AiMessage('user', text),
      ],
    );
    var out = withProductMarkers(plainText(reply.text), [
      for (final c in ctx.candidates)
        if (shareProfile ||
            !RecommendationService.isBlacklisted(c, ctx.blacklist))
          c.product,
    ]);
    if (isSeriousReaction(text)) out = '$out\n\n$safetyNote';
    return out;
  }

  /// The chat bubble shows plain text, but models (Gemini especially) like
  /// markdown: drop the emphasis markers and turn list stars into bullets.
  static String plainText(String s) {
    var t = s.trim();
    t = t.replaceAllMapped(
      RegExp(r'(\*\*|__)(.+?)\1', dotAll: true),
      (m) => m[2]!,
    );
    t = t.replaceAllMapped(
      RegExp(r'(?<![\w*])\*(?!\s)([^*\n]+?)\*(?![\w*])'),
      (m) => m[1]!,
    );
    t = t.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '');
    t = t.replaceAllMapped(
      RegExp(r'^(\s*)[*-]\s+', multiLine: true),
      (m) => '${m[1]}• ',
    );
    return t.replaceAll('`', '');
  }

  /// `[#12]`: the model puts the id of a catalog product right after its name;
  /// the chat turns it into a tappable mini card (see [parseReply]).
  static final _marker = RegExp(r'[ \t]*\[#(\d+)\]');

  /// Splits an answer into the text to show and the product ids it mentions
  /// (in order, without repeats, at most [maxCards]).
  static ({String text, List<int> productIds}) parseReply(String s) {
    final ids = <int>[];
    for (final m in _marker.allMatches(s)) {
      final id = int.parse(m[1]!);
      if (!ids.contains(id)) ids.add(id);
    }
    final text = s
        .replaceAll(_marker, '')
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .trim();
    return (text: text, productIds: ids.take(maxCards).toList());
  }

  /// At most this many product cards under one answer.
  static const maxCards = 3;

  /// Keeps the markers the model wrote (only for products it was allowed to
  /// see) and, when it wrote none, adds them for catalog products whose full
  /// name appears in the answer. Unknown ids are dropped.
  static String withProductMarkers(String answer, List<Product> allowed) {
    final known = {for (final p in allowed) p.id};
    final given = _marker.allMatches(answer).map((m) => int.parse(m[1]!));
    var out = answer.replaceAllMapped(
      _marker,
      (m) => known.contains(int.parse(m[1]!)) ? m[0]! : '',
    );
    if (given.any(known.contains)) return out;
    final lower = answer.toLowerCase();
    final found = <int>[
      for (final p in allowed)
        if (_mentions(lower, p)) p.id,
    ];
    if (found.isEmpty) return out;
    return '$out ${found.take(maxCards).map((id) => '[#$id]').join(' ')}';
  }

  static bool _mentions(String lowerAnswer, Product p) {
    for (final name in {p.name, tr(p.name)}) {
      final n = name.toLowerCase().trim();
      if (n.length >= 6 && lowerAnswer.contains(n)) return true;
    }
    return false;
  }

  /// All facts the model may use. Kept as a pure function so it can be tested.
  /// Without [shareProfile] the Beauty profile and the blacklist stay on the
  /// phone: blacklisted products are simply left out of the catalog the model
  /// sees, so they can still never be recommended.
  static String buildSystemPrompt({
    required PersonalizationContext ctx,
    required String question,
    required String language,
    int? productId,
    bool shareProfile = true,
    StoreContext? stores,
  }) {
    final p = ctx.profile;
    String v(Object? x) => x == null ? 'unknown' : '$x';
    final profile = shareProfile
        ? '''
- skin type: ${v(p.skinType?.label)}
- skin tone: ${v(p.skinTone?.label)}
- undertone: ${v(p.undertone?.label)}
- color type: ${v(p.colorType?.label)}
- skin concerns: ${p.concerns.isEmpty ? 'none' : p.concerns.map((c) => c.label).join(', ')}${_paletteLines(p)}'''
        : 'not shared by the user (do not guess it; if it matters, suggest enabling "personal data for AI" in Settings)';
    final blocked = [
      for (final b in ctx.blacklist)
        if (b.enabled) b.name,
    ];
    // the app's own match for every product (color type, undertone, skin...):
    // the model quotes these facts instead of guessing
    final fits = shareProfile
        ? {
            for (final r in RecommendationService.rank(
              candidates: ctx.candidates,
              profile: ctx.profile,
              blacklist: ctx.blacklist,
            ))
              r.product.id: r,
          }
        : const <int, Recommendation>{};
    final catalog = [
      for (final c in ctx.candidates)
        if (shareProfile ||
            !RecommendationService.isBlacklisted(c, ctx.blacklist))
          '- [#${c.product.id}] ${c.product.brand} ${c.product.name} (${c.product.category}, '
              '${Formatters.price(c.product.price)})'
              '${_actives(c.product)}'
              '${fits[c.product.id] == null ? '' : _fits(fits[c.product.id]!)}'
              '${shareProfile && RecommendationService.isBlacklisted(c, ctx.blacklist) ? ' [CONTAINS BLACKLISTED INGREDIENT - never recommend]' : ''}',
    ].take(maxCatalogLines).toList();
    final focus = _focusProducts(ctx, question, productId, shareProfile);
    final detail = [
      for (final c in focus) _productFacts(c, ctx, shareProfile),
    ].join('\n');
    final blacklistLine = shareProfile
        ? (blocked.isEmpty ? 'none' : blocked.join(', '))
        : 'not shared by the user';
    final shops = _shopLines(stores, shareProfile);
    // The client cuts a message at AiClient.maxMessageChars: facts about the
    // product and the shops come BEFORE the catalog, and when the prompt is too
    // long the catalog loses its tail instead of the facts.
    String assemble(List<String> catalogLines) =>
        '''
You are Cosmetix Assistant, a friendly cosmetics assistant inside a shopping app.
Rules:
- Talk only about cosmetics, ingredients, routines, the user's Beauty Profile and whether products suit them.
- You are NOT a doctor. Never diagnose and never promise that a product will not cause an allergy or a reaction. If the user describes a serious reaction (swelling, trouble breathing, severe rash, burning, pain), tell them to stop using the product and to see a doctor or pharmacist.
- Recommend ONLY products from the CATALOG. Never invent products, prices, shops or ingredients. If a fact is not in the data, say plainly that you have no data.
- Never recommend a product that contains a blacklisted ingredient.
- Catalog lines may have "has:" (acids and actives found in the INCI list; use it for ingredient questions) and "fits:" (reasons computed by the app from the user's Beauty Test, with the match %). Say in a few words why a product suits THIS person, using only those facts, in the answer language. Prefer a higher match. Never praise a shade whose fits say it is another palette's shade.
- Mention only products that DO suit the user, never to say you do not recommend them; just say the other shades belong to another palette.
- Where to buy / nearest shop / cheapest / in stock: use only SHOPS: name the shop, address, distance, price and stock. Say prices and stock are demo values to confirm with the shop, never call them live. No product named: list the nearest shops and ask which product.
- Short answers (under 120 words), plain text: no markdown.
- Each recommended CATALOG product: its full name, then its marker like [#12] right after the name. A marker never stands alone and never follows "or"/"such as". Never invent a marker.
- Answer in $language.

USER BEAUTY PROFILE:
$profile

USER BLACKLIST: $blacklistLine
${detail.isEmpty ? '' : '\nPRODUCT(S) IN QUESTION:\n$detail\n'}
SHOPS (addresses real; prices and stock DEMO, not live):
$shops

CATALOG:
${catalogLines.join('\n')}''';

    var lines = catalog;
    var text = assemble(lines);
    while (text.length > AiClient.maxMessageChars - 100 && lines.length > 6) {
      lines = lines.sublist(0, lines.length - 1);
      text = assemble(lines);
    }
    return text;
  }

  /// The SHOPS section, for tests.
  @visibleForTesting
  static String shopsForTest(StoreContext s, {required bool shareProfile}) =>
      _shopLines(s, shareProfile);

  /// The SHOPS section: nearest shops and, per product, the offers. Distances
  /// are given only when the position is real and the user shared their data.
  static String _shopLines(StoreContext? s, bool shareProfile) {
    if (s == null) return 'no shop data';
    final dist = s.located && shareProfile;
    String km(int m) =>
        m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '$m m';
    String where(StoreInfo x) =>
        '${x.name}, ${x.address}${dist ? ', ${km(x.distanceM)} from the user' : ''}';
    final out = StringBuffer(
      dist
          ? 'Nearest shops to the user:\n'
          : 'Shops (the user position is unknown: do not state distances):\n',
    );
    for (final x in s.nearest) {
      final st = openStatusOf(x.hours, DateTime.now());
      out.writeln('- ${where(x)}${st.isEmpty ? '' : ' ($st)'}');
    }
    for (final e in s.offers.entries) {
      out.writeln('Availability of product [#${e.key}]:');
      for (final o in e.value) {
        final stock = switch (o.level) {
          StockLevel.out => 'out of stock',
          StockLevel.low => 'few left (${o.qty} pcs)',
          StockLevel.inStock =>
            o.qty == null ? 'in stock' : 'in stock (${o.qty} pcs)',
        };
        out.writeln(
          '- ${o.storeName}, ${o.address}${dist ? ', ${km(o.distanceM)}' : ''}: '
          '${Formatters.price(o.price)}, $stock${o.demo ? ' [demo data]' : ''}',
        );
      }
    }
    return out.toString().trimRight();
  }

  /// " | actives: Niacinamide (B3), ..." for the acids and actives in the INCI.
  static String _actives(Product p) {
    final a = IngredientCatalog.activesOf(p);
    return a.isEmpty ? '' : ' | has: ${a.map((g) => g.label).join(', ')}';
  }

  /// " | 84%: palette Весна; undertone Тёплый" from the app's own score.
  static String _fits(Recommendation r) {
    final facts = <String>{for (final x in r.reasons) ?_reasonFact(x)};
    return ' | fits ${r.matchPercent}%${facts.isEmpty ? '' : ': ${facts.join('; ')}'}';
  }

  static String? _reasonFact(MatchReason r) => switch (r.type) {
    MatchReasonType.colorType => 'color type ${r.detail}',
    MatchReasonType.undertone => 'undertone ${r.detail}',
    MatchReasonType.skinType => 'skin ${r.detail}',
    MatchReasonType.concern => 'helps ${r.detail}',
    MatchReasonType.gentle => 'gentle',
    MatchReasonType.preference => 'preference ${r.detail}',
    MatchReasonType.shadeFit => 'shade matches palette ${r.detail}',
    MatchReasonType.shadeOff => 'shade is ${r.detail} palette, NOT the user\'s',
    MatchReasonType.skinShade => 'shade matches skin tone ${r.detail}',
    MatchReasonType.skinShadeOff => 'shade off for skin tone ${r.detail}',
    _ => null,
  };

  /// Extra profile lines: the colours that flatter / do not flatter the type.
  static String _paletteLines(BeautyProfile p) {
    final type = p.colorType;
    if (type == null) return '';
    final pal = ColorPalettes.seasons[type]!;
    String names(List<PaletteColor> l) => l.map((c) => c.name).join(', ');
    return '\n- good makeup colors (${type.label}): ${names(pal.flattering)}'
        '\n- avoid: ${names(pal.avoid)}';
  }

  static List<ProductCandidate> _focusProducts(
    PersonalizationContext ctx,
    String question,
    int? productId,
    bool shareProfile,
  ) {
    if (productId != null) {
      return ctx.candidates.where((c) => c.product.id == productId).toList();
    }
    final q = question.toLowerCase();
    final found = <ProductCandidate>[];
    for (final c in ctx.candidates) {
      if (!shareProfile &&
          RecommendationService.isBlacklisted(c, ctx.blacklist)) {
        continue;
      }
      final Product p = c.product;
      final words = '${p.brand} ${p.name} ${tr(p.name)}'
          .toLowerCase()
          .split(RegExp(r'[^a-zа-яё0-9&+]+'))
          .where((w) => w.length >= 4);
      if (words.any(q.contains)) found.add(c);
    }
    return found.take(2).toList();
  }

  static String _productFacts(
    ProductCandidate c,
    PersonalizationContext ctx,
    bool shareProfile,
  ) {
    final p = c.product;
    final hits = IngredientAnalyzer.analyze(
      c.ingredients,
      ctx.blacklist,
    ).blacklistHits;
    final ranked = RecommendationService.rank(
      candidates: [c],
      profile: ctx.profile,
      blacklist: ctx.blacklist,
    );
    final match = ranked.isEmpty ? null : ranked.first.matchPercent;
    return '''
- ${p.brand} ${p.name} (${p.category}), ${Formatters.price(p.price)}${p.inStock ? '' : ', out of stock'}
  description: ${p.description}
  ingredients: ${c.ingredients.isEmpty ? 'unknown' : c.ingredients.map((i) => '${i.name}${i.isAllergen ? ' (allergen)' : ''}').join(', ')}
${p.inci.isEmpty ? '' : '  full INCI list (published by ${Uri.tryParse(p.sourceUrl)?.host ?? 'the source'}): ${p.inci.length > 700 ? '${p.inci.substring(0, 700)}...' : p.inci}\n'}  made for skin types: ${c.skinTypes.isEmpty ? 'not specified' : c.skinTypes.map((e) => e.label).join(', ')}
  made for color types: ${c.colorTypes.isEmpty ? 'not specified' : c.colorTypes.map((e) => e.label).join(', ')}
${shareProfile ? '''
  blacklisted ingredients found: ${hits.isEmpty ? 'none' : hits.join(', ')}
  match: ${match == null ? 'excluded (blacklist)' : '$match%'}${ranked.isEmpty ? '' : _fits(ranked.first)}''' : ''}''';
  }
}
