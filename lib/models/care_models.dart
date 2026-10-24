/// Models of the cosmetic bag ("Моя косметичка") and the care plan.
library;

/// Date only (no time of day).
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// [d] plus [months] calendar months; the day is clamped to the month length
/// (31 Jan + 1 month = 28/29 Feb).
DateTime addMonths(DateTime d, int months) {
  final total = d.month - 1 + months;
  final year = d.year + total ~/ 12;
  final month = total % 12 + 1;
  final last = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, d.day > last ? last : d.day);
}

/// "2026-10-22": the key of a care day in SQLite.
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime parseDayKey(String s) {
  final p = s.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

/// What the package data says about the product's shelf life.
enum ExpiryState {
  /// Not enough data (no opening date + period after opening, no printed date).
  unknown,
  ok,

  /// Ends within [MyProduct.soonDays] days.
  soon,
  expired,
}

class MyProduct {
  const MyProduct({
    required this.id,
    required this.name,
    this.productId,
    this.brand = '',
    this.category = '',
    this.purchasedAt,
    this.openedAt,
    this.paoMonths,
    this.expiresAt,
    this.notes = '',
  });

  final int id;

  /// The catalog product this one was picked from (null for a free entry).
  final int? productId;
  final String name;
  final String brand;
  final String category;
  final DateTime? purchasedAt;
  final DateTime? openedAt;

  /// "Period after opening" from the jar symbol, in months.
  final int? paoMonths;

  /// The expiry date printed on the package.
  final DateTime? expiresAt;
  final String notes;

  static const soonDays = 30;

  /// Period-after-opening values printed on packages (months).
  static const paoChoices = [3, 6, 9, 12, 18, 24, 36];

  /// The earlier of the printed date and "opened + period after opening".
  /// Null when the package data is not enough to say anything.
  DateTime? get useUntil {
    final dates = <DateTime>[
      if (expiresAt != null) dateOnly(expiresAt!),
      if (openedAt != null && paoMonths != null)
        addMonths(dateOnly(openedAt!), paoMonths!),
    ];
    if (dates.isEmpty) return null;
    return dates.reduce((a, b) => a.isBefore(b) ? a : b);
  }

  /// Whole days left (negative once it has expired); null without data.
  int? daysLeft([DateTime? now]) {
    final end = useUntil;
    if (end == null) return null;
    return end.difference(dateOnly(now ?? DateTime.now())).inDays;
  }

  ExpiryState expiry([DateTime? now]) {
    final d = daysLeft(now);
    if (d == null) return ExpiryState.unknown;
    if (d < 0) return ExpiryState.expired;
    if (d <= soonDays) return ExpiryState.soon;
    return ExpiryState.ok;
  }

  String get title => brand.isEmpty ? name : '$brand — $name';

  factory MyProduct.fromMap(Map<String, Object?> m) {
    DateTime? ms(Object? v) =>
        v == null ? null : DateTime.fromMillisecondsSinceEpoch(v as int);
    return MyProduct(
      id: m['id'] as int,
      productId: m['product_id'] as int?,
      name: m['name'] as String,
      brand: m['brand'] as String? ?? '',
      category: m['category'] as String? ?? '',
      purchasedAt: ms(m['purchased_at']),
      openedAt: ms(m['opened_at']),
      paoMonths: m['pao_months'] as int?,
      expiresAt: ms(m['expires_at']),
      notes: m['notes'] as String? ?? '',
    );
  }
}

enum CarePeriod {
  morning('morning'),
  evening('evening');

  const CarePeriod(this.code);
  final String code;

  static CarePeriod fromCode(String code) => CarePeriod.values.firstWhere(
    (p) => p.code == code,
    orElse: () => CarePeriod.morning,
  );
}

/// One step of the morning or evening plan.
class CareStep {
  const CareStep({
    required this.id,
    required this.period,
    required this.position,
    required this.product,
  });

  final int id;
  final CarePeriod period;
  final int position;
  final MyProduct product;
}

/// "I used this product" for one day and period.
class CareLogEntry {
  const CareLogEntry({
    required this.id,
    required this.day,
    required this.period,
    required this.productName,
    this.myProductId,
  });

  final int id;
  final DateTime day;
  final CarePeriod period;
  final String productName;
  final int? myProductId;

  factory CareLogEntry.fromMap(Map<String, Object?> m) => CareLogEntry(
    id: m['id'] as int,
    day: parseDayKey(m['day'] as String),
    period: CarePeriod.fromCode(m['period'] as String),
    productName: m['product_name'] as String,
    myProductId: m['my_product_id'] as int?,
  );
}
