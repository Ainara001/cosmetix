import 'package:flutter/foundation.dart';

import 'package:cosmetix/models/social_models.dart';
import 'package:cosmetix/repositories/review_repository.dart';

/// Reviews of one product (created by the reviews screen).
class ReviewsProvider extends ChangeNotifier {
  ReviewsProvider(this._repo, this.productId);

  final ReviewRepository _repo;
  final int productId;

  List<Review> reviews = [];
  bool loading = true;

  double get average => reviews.isEmpty
      ? 0
      : reviews.fold<int>(0, (s, r) => s + r.rating) / reviews.length;

  Future<void> load() async {
    try {
      reviews = await _repo.forProduct(productId);
    } catch (e) {
      debugPrint('reviews load failed: $e');
    }
    loading = false;
    notifyListeners();
  }

  Future<void> add({
    required int userId,
    required String author,
    required int rating,
    required String body,
  }) async {
    await _repo.add(
      productId: productId,
      userId: userId,
      author: author,
      rating: rating,
      body: body,
    );
    await load();
  }

  Future<void> edit(Review review, int rating, String body) async {
    await _repo.update(review.id, rating, body);
    await load();
  }

  Future<void> delete(Review review) async {
    await _repo.delete(review.id);
    await load();
  }
}
