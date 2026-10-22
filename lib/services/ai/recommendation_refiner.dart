import 'package:cosmetix/models/ai_models.dart';
import 'package:cosmetix/models/beauty_profile.dart';
import 'package:cosmetix/models/recommendation.dart';
import 'package:cosmetix/services/ai/ai_client.dart';

/// Optional AI re-ranking. It receives ONLY products that already passed the
/// blacklist filter and the local scoring, and it can only reorder them: ids
/// it makes up are dropped, so it can never bring back an excluded product.
class RecommendationRefiner {
  RecommendationRefiner(this._client);

  final AiClient _client;

  static const maxItems = 12;

  /// Product ids in the new order (always a permutation of the input).
  Future<List<int>> refine({
    required BeautyProfile profile,
    required List<Recommendation> candidates,
  }) async {
    final top = candidates.take(maxItems).toList();
    if (top.length < 2) return [for (final r in candidates) r.product.id];
    final lines = [
      for (final r in top)
        '- id ${r.product.id}: ${r.product.brand} ${r.product.name} '
            '(${r.product.category}, local match ${r.matchPercent}%)',
    ].join('\n');
    final reply = await _client.chat(
      json: true,
      temperature: 0.2,
      messages: [
        const AiMessage(
          'system',
          '''
You re-rank cosmetics for one user. You may only reorder the listed products.
Answer with ONE JSON object: {"order": [product ids, best first]} and nothing else.''',
        ),
        AiMessage('user', '''
User profile: skin type ${profile.skinType?.label}, skin tone ${profile.skinTone?.label},
undertone ${profile.undertone?.label}, color type ${profile.colorType?.label},
concerns ${profile.concerns.map((c) => c.label).join(', ')}.
Products:
$lines'''),
      ],
    );
    return applyOrder(
      candidates.map((r) => r.product.id).toList(),
      parseOrder(reply.text),
    );
  }

  static List<int> parseOrder(String raw) {
    final j = extractJsonObject(raw);
    final o = j['order'];
    if (o is! List) throw const AiBadResponse('No "order" list');
    return [
      for (final e in o)
        if (e is int) e else if (e is num && e == e.toInt()) e.toInt(),
    ];
  }

  /// AI order first (only known ids, no duplicates), the rest keeps the local
  /// order. The result is always a permutation of [local].
  static List<int> applyOrder(List<int> local, List<int> ai) {
    final known = local.toSet();
    final out = <int>[];
    for (final id in ai) {
      if (known.contains(id) && !out.contains(id)) out.add(id);
    }
    for (final id in local) {
      if (!out.contains(id)) out.add(id);
    }
    return out;
  }
}
