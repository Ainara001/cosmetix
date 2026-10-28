import 'package:cosmetix/models/ai_models.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/repositories/product_repository.dart';
import 'package:cosmetix/repositories/safety_repository.dart';
import 'package:cosmetix/services/ai/ai_client.dart';

class ClassificationReport {
  const ClassificationReport({
    required this.classified,
    required this.failed,
    required this.stoppedOffline,
  });

  final int classified;
  final int failed;

  /// True when the server went away before everything was processed.
  final bool stoppedOffline;
}

/// Asks the AI who a product suits and caches the answer in SQLite.
/// Runs on demand (Settings) and never when the catalog opens. The model gets
/// only what the app knows about the product and must not invent facts.
class ProductClassifier {
  ProductClassifier(this._client, this._products, this._safety);

  final AiClient _client;
  final ProductRepository _products;
  final SafetyRepository _safety;

  /// Recorded with the cached answer (the proxy picks the real model).
  static const _model = 'claude';

  static const _system = '''
You classify cosmetics for a shopping app. Use ONLY the product data you are given.
If the data does not make a property clear, leave that list empty. Never invent ingredients or claims.
Answer with ONE JSON object and nothing else:
{
  "colorTypes": subset of ["spring","summer","autumn","winter"]  (only for color cosmetics such as lipstick, blush, eyeshadow, foundation),
  "undertones": subset of ["warm","cool","neutral"]               (only for color cosmetics),
  "skinTypes": subset of ["dry","normal","oily","combination","sensitive"],
  "concerns": subset of ["dryness","pigmentation","acne","sensitivity","aging"],
  "confidence": number 0..1,
  "explanation": "one short sentence"
}''';

  Future<ProductClassification> classify(Product p) async {
    final ingredients = await _safety.ingredientsOf(p.id);
    final user =
        '''
Brand: ${p.brand}
Name: ${p.name}
Category: ${p.category}
Zone: ${p.zone}
Description: ${p.description}
Ingredients: ${ingredients.isEmpty ? 'unknown' : ingredients.map((i) => i.name).join(', ')}''';
    final reply = await _client.chat(
      json: true,
      temperature: 0.1,
      messages: [const AiMessage('system', _system), AiMessage('user', user)],
    );
    return sanitize(p, ProductClassification.parse(reply.text));
  }

  /// Skincare gets no color traits, so the model cannot "invent" shades.
  static ProductClassification sanitize(Product p, ProductClassification c) {
    final decorative = p.category == 'Макияж';
    return ProductClassification(
      colorTypes: decorative ? c.colorTypes : const {},
      undertones: decorative ? c.undertones : const {},
      skinTypes: c.skinTypes,
      concerns: c.concerns,
      confidence: c.confidence,
      explanation: c.explanation,
    );
  }

  /// Classifies products that have no cached answer yet.
  Future<ClassificationReport> classifyPending(
    int userId, {
    int limit = 40,
    void Function(int done, int total)? onProgress,
  }) async {
    final pending = (await _products.unclassified(userId)).take(limit).toList();
    var ok = 0, failed = 0;
    for (var i = 0; i < pending.length; i++) {
      onProgress?.call(i, pending.length);
      try {
        final c = await classify(pending[i]);
        await _products.saveAiClassification(pending[i].id, _model, c);
        ok++;
      } on AiBadResponse {
        failed++; // keep going, this product is retried next time
      } on AiException {
        return ClassificationReport(
          classified: ok,
          failed: failed,
          stoppedOffline: true,
        );
      }
    }
    onProgress?.call(pending.length, pending.length);
    return ClassificationReport(
      classified: ok,
      failed: failed,
      stoppedOffline: false,
    );
  }
}
