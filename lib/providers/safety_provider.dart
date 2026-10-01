import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/foundation.dart';

import 'package:cosmetix/models/safety_models.dart';
import 'package:cosmetix/repositories/safety_repository.dart';
import 'package:cosmetix/services/ingredient_analyzer.dart';

/// Blacklist of ingredients, composition analysis and the reactions diary.
class SafetyProvider extends ChangeNotifier {
  SafetyProvider(this._repo);

  final SafetyRepository _repo;

  List<BlacklistItem> blacklist = [];
  List<Reaction> reactions = [];
  int? _userId;

  Future<void> load(int userId) async {
    _userId = userId;
    try {
      blacklist = await _repo.blacklist(userId);
      reactions = await _repo.reactions(userId);
    } catch (e) {
      debugPrint('safety load failed: $e');
    }
    notifyListeners();
  }

  void reset() {
    blacklist = [];
    reactions = [];
    _userId = null;
    notifyListeners();
  }

  Future<IngredientAnalysis> analyze(int productId) async {
    final ingredients = await _repo.ingredientsOf(productId);
    return IngredientAnalyzer.analyze(ingredients, blacklist);
  }

  // ---- blacklist ----

  Future<void> toggleBlacklist(BlacklistItem item, bool enabled) async {
    await _repo.setBlacklistEnabled(item.id, enabled);
    blacklist = await _repo.blacklist(_userId!);
    notifyListeners();
  }

  /// Returns an error text or null.
  Future<String?> addCustom(String name) async {
    final text = name.trim();
    if (text.length < 2) return tr('Название слишком короткое');
    if (blacklist.any((b) => b.name.toLowerCase() == text.toLowerCase())) {
      return tr('Этот компонент уже есть в списке');
    }
    await _repo.addCustom(_userId!, text);
    blacklist = await _repo.blacklist(_userId!);
    notifyListeners();
    return null;
  }

  Future<void> deleteBlacklist(BlacklistItem item) async {
    await _repo.deleteBlacklistItem(item.id);
    blacklist = await _repo.blacklist(_userId!);
    notifyListeners();
  }

  // ---- reactions ----

  Future<Reaction?> reactionById(int id) => _repo.reactionById(id);

  Future<void> saveReaction({
    int? id,
    required int productId,
    required String title,
    required int severity,
    required DateTime date,
    String notes = '',
  }) async {
    if (id == null) {
      await _repo.addReaction(
        userId: _userId!,
        productId: productId,
        title: title,
        severity: severity,
        date: date,
        notes: notes,
      );
    } else {
      await _repo.updateReaction(
        id: id,
        productId: productId,
        title: title,
        severity: severity,
        date: date,
        notes: notes,
      );
    }
    reactions = await _repo.reactions(_userId!);
    notifyListeners();
  }

  Future<void> deleteReaction(Reaction r) async {
    await _repo.deleteReaction(r.id);
    reactions = await _repo.reactions(_userId!);
    notifyListeners();
  }
}
