import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/utils/formatters.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/models/recommendation.dart';
import 'package:cosmetix/models/social_models.dart';
import 'package:cosmetix/services/ai/ai_config.dart';
import 'package:cosmetix/services/ai/ollama_client.dart';
import 'package:cosmetix/services/ingredient_analyzer.dart';
import 'package:cosmetix/services/recommendation_service.dart';

/// The chat assistant: a real Ollama model that knows the user's Beauty
/// Profile, blacklist and (when relevant) the product being discussed.
/// Throws [AiException] when the server is not available: the caller shows a
/// friendly message, nothing else in the app depends on the chat.
class AssistantService {
  AssistantService(this._reco, this._client, this._config);

  final RecommendationService _reco;
  final OllamaClient _client;
  final AiConfig Function() _config;

  /// How many previous messages are sent as conversation context.
  static const historyLimit = 8;

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
  }) async {
    final ctx = await _reco.loadContext(userId);
    final system = buildSystemPrompt(
      ctx: ctx,
      question: text,
      productId: productId,
      language: currentLang.englishName,
    );
    final recent = history.length > historyLimit
        ? history.sublist(history.length - historyLimit)
        : history;
    final answer = await _client.chat(
      model: _config().textModel,
      temperature: 0.4,
      messages: [
        OllamaMessage('system', system),
        for (final m in recent)
          OllamaMessage(m.isUser ? 'user' : 'assistant', m.text),
        OllamaMessage('user', text),
      ],
    );
    var out = answer.trim();
    if (isSeriousReaction(text)) out = '$out\n\n$safetyNote';
    return out;
  }

  /// All facts the model may use. Kept as a pure function so it can be tested.
  static String buildSystemPrompt({
    required PersonalizationContext ctx,
    required String question,
    required String language,
    int? productId,
  }) {
    final p = ctx.profile;
    String v(Object? x) => x == null ? 'unknown' : '$x';
    final profile =
        '''
- skin type: ${v(p.skinType?.label)}
- skin tone: ${v(p.skinTone?.label)}
- undertone: ${v(p.undertone?.label)}
- color type: ${v(p.colorType?.label)}
- skin concerns: ${p.concerns.isEmpty ? 'none' : p.concerns.map((c) => c.label).join(', ')}''';
    final blocked = [
      for (final b in ctx.blacklist)
        if (b.enabled) b.name,
    ];
    final catalog = [
      for (final c in ctx.candidates)
        '- ${c.product.brand} ${c.product.name} (${c.product.category}, '
            '${Formatters.price(c.product.price)})'
            '${RecommendationService.isBlacklisted(c, ctx.blacklist) ? ' [CONTAINS BLACKLISTED INGREDIENT - never recommend]' : ''}',
    ];
    final focus = _focusProducts(ctx, question, productId);
    final detail = [for (final c in focus) _productFacts(c, ctx)].join('\n');
    return '''
You are Cosmetix Assistant, a friendly cosmetics assistant inside a shopping app.
Rules:
- Talk only about cosmetics, ingredients, routines, the user's Beauty Profile and whether products suit them.
- You are NOT a doctor. Never diagnose. If the user describes a serious reaction (swelling, trouble breathing, severe rash, burning, pain), tell them to stop using the product and to see a doctor or pharmacist.
- Recommend ONLY products from the CATALOG below. Never invent products, prices or ingredients. If you do not know, say so.
- Never recommend a product that contains a blacklisted ingredient.
- Base suitability answers on the Beauty Profile and the ingredient facts you are given.
- Keep answers short (under 120 words).
- Answer in $language.

USER BEAUTY PROFILE:
$profile

USER BLACKLIST (ingredients to avoid): ${blocked.isEmpty ? 'none' : blocked.join(', ')}

CATALOG:
${catalog.join('\n')}
${detail.isEmpty ? '' : '\nPRODUCT(S) IN QUESTION:\n$detail'}''';
  }

  static List<ProductCandidate> _focusProducts(
    PersonalizationContext ctx,
    String question,
    int? productId,
  ) {
    if (productId != null) {
      return ctx.candidates.where((c) => c.product.id == productId).toList();
    }
    final q = question.toLowerCase();
    final found = <ProductCandidate>[];
    for (final c in ctx.candidates) {
      final Product p = c.product;
      final words = '${p.brand} ${p.name} ${tr(p.name)}'
          .toLowerCase()
          .split(RegExp(r'[^a-zа-яё0-9&+]+'))
          .where((w) => w.length >= 4);
      if (words.any(q.contains)) found.add(c);
    }
    return found.take(2).toList();
  }

  static String _productFacts(ProductCandidate c, PersonalizationContext ctx) {
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
  blacklisted ingredients found: ${hits.isEmpty ? 'none' : hits.join(', ')}
  local match with the user: ${match == null ? 'excluded (blacklist)' : '$match%'}''';
  }
}
