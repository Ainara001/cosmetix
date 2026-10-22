import 'package:flutter/foundation.dart';

import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/models/care_models.dart';
import 'package:cosmetix/repositories/care_repository.dart';

/// The cosmetic bag, the morning / evening plan and today's marks.
class CareProvider extends ChangeNotifier {
  CareProvider(this._repo, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final CareRepository _repo;
  final DateTime Function() _clock;

  List<MyProduct> bag = [];
  final Map<CarePeriod, List<CareStep>> _steps = {
    for (final p in CarePeriod.values) p: [],
  };

  /// Keys "period:myProductId" of the products used today.
  Set<String> _usedToday = {};
  List<CareLogEntry> history = [];
  bool loading = false;
  int? _userId;

  DateTime get today => dateOnly(_clock());

  List<CareStep> steps(CarePeriod period) => _steps[period]!;

  Future<void> load(int userId) async {
    _userId = userId;
    loading = true;
    notifyListeners();
    try {
      bag = await _repo.bag(userId);
      for (final p in CarePeriod.values) {
        _steps[p] = await _repo.steps(userId, p);
      }
      await _loadUsage(userId);
    } catch (e) {
      debugPrint('care load failed: $e');
    }
    loading = false;
    notifyListeners();
  }

  Future<void> _loadUsage(int userId) async {
    final logs = await _repo.logsOfDay(userId, today);
    _usedToday = {
      for (final l in logs)
        if (l.myProductId != null) '${l.period.code}:${l.myProductId}',
    };
    history = await _repo.history(userId, now: _clock());
  }

  void reset() {
    bag = [];
    for (final p in CarePeriod.values) {
      _steps[p] = [];
    }
    _usedToday = {};
    history = [];
    _userId = null;
    notifyListeners();
  }

  // ---- bag ----

  MyProduct? byId(int id) {
    for (final p in bag) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Products that are expired or end within 30 days.
  List<MyProduct> get attention => [
    for (final p in bag)
      if (p.expiry(_clock()) == ExpiryState.expired ||
          p.expiry(_clock()) == ExpiryState.soon)
        p,
  ];

  /// Returns an error text or null.
  Future<String?> saveProduct(MyProduct p, {bool isNew = false}) async {
    final userId = _userId;
    if (userId == null) return tr('Сначала войдите в аккаунт');
    final problem = validate(p, now: _clock());
    if (problem != null) return problem;
    try {
      if (isNew) {
        await _repo.addToBag(userId, p);
      } else {
        await _repo.updateBagItem(p);
      }
      await load(userId);
      return null;
    } catch (e) {
      debugPrint('save bag item failed: $e');
      return tr('Не удалось сохранить средство');
    }
  }

  /// Checks the dates: opening can not be before the purchase, nothing is
  /// in the future (except the printed expiry date), the name is required.
  static String? validate(MyProduct p, {DateTime? now}) {
    final today = dateOnly(now ?? DateTime.now());
    if (p.name.trim().length < 2) return tr('Введите название средства');
    if (p.purchasedAt != null && dateOnly(p.purchasedAt!).isAfter(today)) {
      return tr('Дата покупки не может быть в будущем');
    }
    if (p.openedAt != null && dateOnly(p.openedAt!).isAfter(today)) {
      return tr('Дата вскрытия не может быть в будущем');
    }
    if (p.purchasedAt != null &&
        p.openedAt != null &&
        dateOnly(p.openedAt!).isBefore(dateOnly(p.purchasedAt!))) {
      return tr('Вскрыто раньше, чем куплено? Проверьте даты');
    }
    if (p.paoMonths != null && p.openedAt == null) {
      return tr('Укажите дату вскрытия, чтобы считать срок после вскрытия');
    }
    return null;
  }

  Future<void> deleteProduct(MyProduct p) async {
    final userId = _userId;
    if (userId == null) return;
    await _repo.removeFromBag(p.id);
    await load(userId);
  }

  // ---- plan ----

  bool inPlan(CarePeriod period, int myProductId) =>
      _steps[period]!.any((s) => s.product.id == myProductId);

  /// Returns an error text or null.
  Future<String?> addStep(CarePeriod period, MyProduct product) async {
    final userId = _userId;
    if (userId == null) return tr('Сначала войдите в аккаунт');
    if (inPlan(period, product.id)) return tr('Это средство уже в плане');
    await _repo.addStep(userId, period, product.id);
    _steps[period] = await _repo.steps(userId, period);
    notifyListeners();
    return null;
  }

  Future<void> removeStep(CareStep step) async {
    final userId = _userId;
    if (userId == null) return;
    await _repo.removeStep(step.id);
    _steps[step.period] = await _repo.steps(userId, step.period);
    notifyListeners();
  }

  /// Moves a step by [delta] places (-1 up, +1 down).
  Future<void> move(CareStep step, int delta) async {
    final userId = _userId;
    if (userId == null) return;
    final list = [..._steps[step.period]!];
    final from = list.indexWhere((s) => s.id == step.id);
    final to = from + delta;
    if (from < 0 || to < 0 || to >= list.length) return;
    final item = list.removeAt(from);
    list.insert(to, item);
    await _repo.reorder([for (final s in list) s.id]);
    _steps[step.period] = await _repo.steps(userId, step.period);
    notifyListeners();
  }

  // ---- today's marks ----

  bool isUsedToday(CarePeriod period, int myProductId) =>
      _usedToday.contains('${period.code}:$myProductId');

  /// How many steps of [period] are marked today.
  int doneCount(CarePeriod period) =>
      _steps[period]!.where((s) => isUsedToday(period, s.product.id)).length;

  Future<void> setUsed(CareStep step, bool used) async {
    final userId = _userId;
    if (userId == null) return;
    await _repo.setUsed(
      userId: userId,
      day: today,
      period: step.period,
      product: step.product,
      used: used,
    );
    await _loadUsage(userId);
    notifyListeners();
  }

  /// History grouped by day (newest first).
  Map<DateTime, List<CareLogEntry>> get historyByDay {
    final out = <DateTime, List<CareLogEntry>>{};
    for (final e in history) {
      out.putIfAbsent(e.day, () => []).add(e);
    }
    return out;
  }
}
