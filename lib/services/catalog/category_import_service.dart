import 'package:cosmetix/models/ai_models.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/repositories/category_review_repository.dart';
import 'package:cosmetix/services/ai/ai_client.dart';
import 'package:cosmetix/services/ai/product_classifier.dart';
import 'package:cosmetix/services/catalog/category_normalizer.dart';

/// What happened to one imported category.
class ImportedCategory {
  const ImportedCategory(this.category, {this.queueId});

  final NormalizedCategory category;

  /// Row in the review queue when a person has to decide.
  final int? queueId;

  /// The unified category, or null while it waits for a person.
  String? get typeKey => category.typeKey;
}

/// Puts the category of an imported shop product into the unified list.
///
/// Sure cases get their category at once. Everything else goes to the review
/// queue, together with a hint from the AI classifier when one is available.
/// The hint is only text for the reviewer: it never decides the category
/// (the classifier answers "who is this product for", it does not know the
/// shop's category list).
class CategoryImportService {
  CategoryImportService(this._normalizer, this._queue, [this._classifier]);

  final CategoryNormalizer _normalizer;
  final CategoryReviewRepository _queue;
  final ProductClassifier? _classifier;

  Future<ImportedCategory> process({
    required String store,
    required String rawCategory,
    String brand = '',
    String productName = '',
  }) async {
    final c = _normalizer.normalize(rawCategory);
    if (!c.needsReview) return ImportedCategory(c);
    final hint = await _hint(rawCategory, brand, productName);
    final id = await _queue.enqueue(
      c,
      store: store,
      productName: productName,
      aiHint: hint,
    );
    return ImportedCategory(c, queueId: id);
  }

  Future<String> _hint(String category, String brand, String name) async {
    final classifier = _classifier;
    if (classifier == null) return '';
    try {
      final c = await classifier.classify(
        Product(
          id: 0,
          brand: brand,
          name: name,
          category: category,
          zone: '',
          price: 0,
          inStock: true,
          art: 'bottle',
          color: 0,
          description: '',
          naturalPercent: 0,
          createdAt: 0,
        ),
      );
      return hintText(c);
    } on AiException {
      return ''; // no hint is better than a failed import
    }
  }

  /// The classifier's answer as one line for the reviewer.
  static String hintText(ProductClassification c) {
    if (c.isEmpty) return '';
    final parts = [
      if (c.skinTypes.isNotEmpty)
        'типы кожи: ${c.skinTypes.map((e) => e.label).join(', ')}',
      if (c.concerns.isNotEmpty)
        'задачи: ${c.concerns.map((e) => e.label).join(', ')}',
      if (c.colorTypes.isNotEmpty)
        'цветотипы: ${c.colorTypes.map((e) => e.label).join(', ')}',
    ];
    final tail = c.explanation.isEmpty ? '' : ' — ${c.explanation}';
    return 'ИИ (подсказка, не решение): ${parts.join('; ')}$tail';
  }
}
