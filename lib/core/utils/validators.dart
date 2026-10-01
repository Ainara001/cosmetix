/// Form validators. Every method returns an error text or null when valid.
class Validators {
  Validators._();

  static final _emailRe = RegExp(r'^[\w.+-]+@([\w-]+\.)+[\w-]{2,}$');
  static final _nameRe = RegExp(r"^[A-Za-zА-Яа-яЁёӘәҒғҚқҢңӨөҰұҮүҺһІі\s'-]+$");

  static String? required(String? v, [String field = 'Поле']) {
    if (v == null || v.trim().isEmpty) {
      return '$field обязательно для заполнения';
    }
    return null;
  }

  static String? name(String? v, [String field = 'Имя']) {
    final text = v?.trim() ?? '';
    if (text.isEmpty) return '$field обязательно для заполнения';
    if (text.length < 2) return '$field слишком короткое (минимум 2 буквы)';
    if (text.length > 40) return '$field слишком длинное (максимум 40)';
    if (!_nameRe.hasMatch(text)) return '$field может содержать только буквы';
    return null;
  }

  static String? email(String? v) {
    final text = v?.trim() ?? '';
    if (text.isEmpty) return 'Введите email';
    if (!_emailRe.hasMatch(text)) {
      return 'Некорректный email, например name@mail.com';
    }
    return null;
  }

  /// At least 8 characters with a letter and a digit.
  static String? password(String? v) {
    final text = v ?? '';
    if (text.isEmpty) return 'Введите пароль';
    if (text.length < 8) return 'Пароль должен быть не короче 8 символов';
    if (!RegExp(r'[A-Za-zА-Яа-я]').hasMatch(text) ||
        !RegExp(r'\d').hasMatch(text)) {
      return 'Пароль должен содержать буквы и цифры';
    }
    return null;
  }

  /// Login only checks that something was typed.
  static String? loginPassword(String? v) {
    if (v == null || v.isEmpty) return 'Введите пароль';
    return null;
  }

  static String? confirmPassword(String? v, String original) {
    if (v == null || v.isEmpty) return 'Повторите пароль';
    if (v != original) return 'Пароли не совпадают';
    return null;
  }

  /// Optional phone: 10–15 digits, may start with +.
  static String? phone(String? v) {
    final text = v?.trim() ?? '';
    if (text.isEmpty) return null;
    final digits = text.replaceAll(RegExp(r'[\s()-]'), '');
    if (!RegExp(r'^\+?\d{10,15}$').hasMatch(digits)) {
      return 'Введите номер в формате +7 707 123 45 67';
    }
    return null;
  }

  /// Optional whole number >= 0.
  static String? amount(String? v) {
    final text = v?.trim() ?? '';
    if (text.isEmpty) return null;
    final n = int.tryParse(text);
    if (n == null) return 'Только цифры';
    if (n < 0) return 'Не может быть отрицательным';
    return null;
  }

  static String? text(
    String? v, {
    int min = 1,
    int max = 500,
    String field = 'Поле',
  }) {
    final text = v?.trim() ?? '';
    if (text.isEmpty) return '$field обязательно для заполнения';
    if (text.length < min) {
      return '$field слишком короткое (минимум $min символов)';
    }
    if (text.length > max) return '$field слишком длинное (максимум $max)';
    return null;
  }
}
