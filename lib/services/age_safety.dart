import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/services/ingredient_catalog.dart';
import 'package:cosmetix/services/routine_checks.dart';

/// Age limits for strong active ingredients. Only what the sources confirm:
///
/// - adapalene (a retinoid) is approved from 12 years; for a child under 12
///   the label says "ask a doctor" (Differin Drug Facts, FDA approval 2016);
/// - for benzoyl peroxide health services advise talking to a doctor before a
///   child under 12 uses it (HealthLinkBC, Mayo Clinic).
///
/// For acids no age limit was found in the sources, so a child gets a gentle
/// "ask a doctor" note instead of a ban. Not medical advice.
///
/// Only the year of birth is stored, so the age is taken one year LOWER than
/// it may really be: the safer side for a child who has not had the birthday
/// yet this year.
class AgeSafety {
  AgeSafety._();

  /// Below this age retinoids and benzoyl peroxide are not offered.
  static const childLimit = 12;

  static const _childBlocked = {'retinoid', 'benzoyl'};

  /// A year of birth the profile accepts (the person is at most 110).
  static bool validBirthYear(int year, {DateTime? now}) {
    final y = (now ?? DateTime.now()).year;
    return year <= y && year >= y - 110;
  }

  /// The careful age for a year of birth, or null when it is not given.
  static int? ageFromBirthYear(int? birthYear, {DateTime? now}) {
    if (birthYear == null) return null;
    final y = (now ?? DateTime.now()).year;
    return (y - birthYear - 1).clamp(0, 120);
  }

  /// True when a child of [age] should not get a product with [actives].
  static bool blocks(int? age, Set<String> actives) =>
      age != null && age < childLimit && actives.any(_childBlocked.contains);

  /// Why a product is not offered at [age], or null when it is fine.
  static String? blockReason(int? age, Product product) {
    if (!blocks(age, IngredientCatalog.of(product))) return null;
    return 'Это средство с ретиноидом или бензоилпероксидом не подходит '
        'в вашем возрасте. Спросите врача.';
  }

  /// Warnings about one product for the age of the user.
  static List<RoutineIssue> issues(int? age, RoutineItem item) {
    if (age == null || age >= childLimit) return const [];
    if (blocks(age, item.actives)) {
      return [
        RoutineIssue(
          IssueSeverity.avoid,
          '«{a}» содержит ретиноид или бензоилпероксид: детям до {n} лет их не предлагают. Спросите врача.',
          {'a': item.title, 'n': childLimit},
        ),
      ];
    }
    if (item.actives.any(ActiveRules.acids.contains)) {
      return [
        RoutineIssue(
          IssueSeverity.caution,
          '«{a}» содержит кислоту: возрастных рекомендаций для детей до {n} лет мы не нашли, сначала спросите врача.',
          {'a': item.title, 'n': childLimit},
        ),
      ];
    }
    return const [];
  }
}
