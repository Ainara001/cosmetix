import 'package:cosmetix/core/i18n/tr.dart';

/// Form validators. Every method returns an error text or null when valid.
class Validators {
  Validators._();

  static final _emailRe = RegExp(r'^[\w.+-]+@([\w-]+\.)+[\w-]{2,}$');
  static final _nameRe = RegExp(r"^[A-Za-zА-Яа-яЁёӘәҒғҚқҢңӨөҰұҮүҺһІі\s'-]+$");

  static String? required(String? v, [String field = 'Поле']) {
    if (v == null || v.trim().isEmpty) {
      return trf('{field} обязательно для заполнения', {'field': tr(field)});
    }
    return null;
  }

  static String? name(String? v, [String field = 'Имя']) {
    final text = v?.trim() ?? '';
    if (text.isEmpty) {
      return trf('{field} обязательно для заполнения', {'field': tr(field)});
    }
    if (text.length < 2) {
      return trf('{field} слишком короткое (минимум 2 буквы)', {
        'field': tr(field),
      });
    }
    if (text.length > 40) {
      return trf('{field} слишком длинное (максимум 40)', {'field': tr(field)});
    }
    if (!_nameRe.hasMatch(text)) {
      return trf('{field} может содержать только буквы', {'field': tr(field)});
    }
    return null;
  }

  static String? email(String? v) {
    final text = v?.trim() ?? '';
    if (text.isEmpty) return tr('Введите email');
    if (text.length > 254) return tr('Email слишком длинный (максимум 254)');
    if (!_emailRe.hasMatch(text)) {
      return tr('Некорректный email, например name@mail.com');
    }
    return null;
  }

  /// At least 8 characters with a letter and a digit.
  static String? password(String? v) {
    final text = v ?? '';
    if (text.isEmpty) return tr('Введите пароль');
    if (text.length < 8) return tr('Пароль должен быть не короче 8 символов');
    if (text.length > 64) return tr('Пароль слишком длинный (максимум 64)');
    if (!RegExp(r'[A-Za-zА-Яа-я]').hasMatch(text) ||
        !RegExp(r'\d').hasMatch(text)) {
      return tr('Пароль должен содержать буквы и цифры');
    }
    return null;
  }

  /// Login only checks that something was typed.
  static String? loginPassword(String? v) {
    if (v == null || v.isEmpty) return tr('Введите пароль');
    return null;
  }

  static String? confirmPassword(String? v, String original) {
    if (v == null || v.isEmpty) return tr('Повторите пароль');
    if (v != original) return tr('Пароли не совпадают');
    return null;
  }

  /// Optional phone: 10–15 digits, may start with +.
  static String? phone(String? v) {
    final text = v?.trim() ?? '';
    if (text.isEmpty) return null;
    final digits = text.replaceAll(RegExp(r'[\s()-]'), '');
    if (!RegExp(r'^\+?\d{10,15}$').hasMatch(digits)) {
      return tr('Введите номер в формате +7 707 123 45 67');
    }
    return null;
  }

  /// Optional whole number in 0..[max].
  static String? amount(String? v, {int max = 50000}) {
    final text = v?.trim() ?? '';
    if (text.isEmpty) return null;
    final n = int.tryParse(text);
    if (n == null) return tr('Только цифры');
    if (n < 0) return tr('Не может быть отрицательным');
    if (n > max) return trf('Не больше {max}', {'max': max});
    return null;
  }

  static String? text(
    String? v, {
    int min = 1,
    int max = 500,
    String field = 'Поле',
  }) {
    final text = v?.trim() ?? '';
    if (text.isEmpty) {
      return trf('{field} обязательно для заполнения', {'field': tr(field)});
    }
    if (text.length < min) {
      return trf('{field} слишком короткое (минимум {min} символов)', {
        'field': tr(field),
        'min': min,
      });
    }
    if (text.length > max) {
      return trf('{field} слишком длинное (максимум {max})', {
        'field': tr(field),
        'max': max,
      });
    }
    return null;
  }
}
