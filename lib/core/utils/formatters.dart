enum AppCurrency {
  kzt('Тенге (₸)', 'тг', 1),
  rub('Рубль (₽)', '₽', 0.19),
  usd('Доллар (\$)', '\$', 0.002);

  const AppCurrency(this.label, this.symbol, this.rate);

  final String label;
  final String symbol;

  /// How many units of this currency are in 1 tenge.
  final double rate;

  static AppCurrency fromName(String? name) => AppCurrency.values.firstWhere(
    (c) => c.name == name,
    orElse: () => AppCurrency.kzt,
  );
}

class Formatters {
  Formatters._();

  /// 2500 -> "2 500 тг" (amounts are stored in tenge).
  static String price(int tenge, [AppCurrency currency = AppCurrency.kzt]) {
    final value = tenge * currency.rate;
    if (currency == AppCurrency.usd) {
      return '${_group(value.toStringAsFixed(2).split('.').first)}.'
          '${value.toStringAsFixed(2).split('.').last} ${currency.symbol}';
    }
    return '${_group(value.round().toString())} ${currency.symbol}';
  }

  static String _group(String digits) {
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(' ');
      buf.write(digits[i]);
    }
    return buf.toString();
  }

  static const _months = [
    'Января',
    'Февраля',
    'Марта',
    'Апреля',
    'Мая',
    'Июня',
    'Июля',
    'Августа',
    'Сентября',
    'Октября',
    'Ноября',
    'Декабря',
  ];

  /// "12 Октября 2025"
  static String date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} ${d.year}';

  /// "2 часа назад", "вчера", "3 дня назад"
  static String ago(DateTime d, {DateTime? now}) {
    final diff = (now ?? DateTime.now()).difference(d);
    if (diff.inMinutes < 1) return 'только что';
    if (diff.inHours < 1) return '${diff.inMinutes} мин назад';
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return '$h ${_plural(h, 'час', 'часа', 'часов')} назад';
    }
    if (diff.inDays == 1) return 'вчера';
    if (diff.inDays < 30) {
      final n = diff.inDays;
      return '$n ${_plural(n, 'день', 'дня', 'дней')} назад';
    }
    return date(d);
  }

  static String _plural(int n, String one, String few, String many) {
    final m10 = n % 10, m100 = n % 100;
    if (m10 == 1 && m100 != 11) return one;
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
    return many;
  }

  static String plural(int n, String one, String few, String many) =>
      _plural(n, one, few, many);
}
