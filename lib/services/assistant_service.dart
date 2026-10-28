import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/utils/formatters.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/models/recommendation.dart';
import 'package:cosmetix/models/social_models.dart';
import 'package:cosmetix/services/ai/ai_client.dart';
import 'package:cosmetix/services/ingredient_analyzer.dart';
import 'package:cosmetix/services/recommendation_service.dart';

/// The chat assistant: an AI model (through the Cosmetix AI proxy) that knows the
/// catalog and, only when the user agreed (`shareProfile`), their Beauty
/// Profile and blacklist, plus the product being discussed.
/// Throws [AiException] when the server is not available: the caller shows a
/// friendly message, nothing else in the app depends on the chat.
class AssistantService {
  AssistantService(this._reco, this._client);

  final RecommendationService _reco;
  final AiClient _client;

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
    final system = buildSystemPrompt(
      ctx: ctx,
      question: text,
      productId: productId,
      language: currentLang.englishName,
      shareProfile: shareProfile,
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
    var out = plainText(reply.text);
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
  }) {
    final p = ctx.profile;
    String v(Object? x) => x == null ? 'unknown' : '$x';
    final profile = shareProfile
        ? '''
- skin type: ${v(p.skinType?.label)}
- skin tone: ${v(p.skinTone?.label)}
- undertone: ${v(p.undertone?.label)}
- color type: ${v(p.colorType?.label)}
- skin concerns: ${p.concerns.isEmpty ? 'none' : p.concerns.map((c) => c.label).join(', ')}'''
        : 'not shared by the user (do not guess it; if it matters, suggest enabling "personal data for AI" in Settings)';
    final blocked = [
      for (final b in ctx.blacklist)
        if (b.enabled) b.name,
    ];
    final catalog = [
      for (final c in ctx.candidates)
        if (shareProfile ||
            !RecommendationService.isBlacklisted(c, ctx.blacklist))
          '- ${c.product.brand} ${c.product.name} (${c.product.category}, '
              '${Formatters.price(c.product.price)})'
              '${shareProfile && RecommendationService.isBlacklisted(c, ctx.blacklist) ? ' [CONTAINS BLACKLISTED INGREDIENT - never recommend]' : ''}',
    ].take(maxCatalogLines).toList();
    final focus = _focusProducts(ctx, question, productId, shareProfile);
    final detail = [
      for (final c in focus) _productFacts(c, ctx, shareProfile),
    ].join('\n');
    final blacklistLine = shareProfile
        ? (blocked.isEmpty ? 'none' : blocked.join(', '))
        : 'not shared by the user';
    return '''
You are Cosmetix Assistant, a friendly cosmetics assistant inside a shopping app.
Rules:
- Talk only about cosmetics, ingredients, routines, the user's Beauty Profile and whether products suit them.
- You are NOT a doctor. Never diagnose and never promise that a product will not cause an allergy or a reaction. If the user describes a serious reaction (swelling, trouble breathing, severe rash, burning, pain), tell them to stop using the product and to see a doctor or pharmacist.
- Recommend ONLY products from the CATALOG below. Never invent products, prices, stores or ingredients. If a product or fact is not in the data, say plainly that you have no data about it.
- Never recommend a product that contains a blacklisted ingredient.
- Base suitability answers on the Beauty Profile and the ingredient facts you are given, and explain them in simple words.
- Keep answers short (under 120 words).
- Write plain text: no markdown (no **bold**, no # headings, no tables).
- Answer in $language.

USER BEAUTY PROFILE:
$profile

USER BLACKLIST (ingredients to avoid): $blacklistLine

CATALOG:
${catalog.join('\n')}
${detail.isEmpty ? '' : '\nPRODUCT(S) IN QUESTION:\n$detail'}''';
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
  made for skin types: ${c.skinTypes.isEmpty ? 'not specified' : c.skinTypes.map((e) => e.label).join(', ')}
  made for color types: ${c.colorTypes.isEmpty ? 'not specified' : c.colorTypes.map((e) => e.label).join(', ')}
${shareProfile ? '''
  blacklisted ingredients found: ${hits.isEmpty ? 'none' : hits.join(', ')}
  local match with the user: ${match == null ? 'excluded (blacklist)' : '$match%'}''' : ''}''';
  }
}
