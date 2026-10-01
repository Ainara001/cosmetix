import 'package:flutter_test/flutter_test.dart';

import 'package:cosmetix/core/utils/formatters.dart';
import 'package:cosmetix/core/utils/validators.dart';

void main() {
  group('Validators', () {
    test('email', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email('abc'), isNotNull);
      expect(Validators.email('a@b'), isNotNull);
      expect(Validators.email('ainara.rust@gmail.com'), isNull);
    });

    test('password needs 8 chars, letters and digits', () {
      expect(Validators.password('abc123'), isNotNull);
      expect(Validators.password('abcdefgh'), isNotNull);
      expect(Validators.password('12345678'), isNotNull);
      expect(Validators.password('Cosmetix123'), isNull);
    });

    test('name', () {
      expect(Validators.name(''), isNotNull);
      expect(Validators.name('A'), isNotNull);
      expect(Validators.name('Anna123'), isNotNull);
      expect(Validators.name('Айнара'), isNull);
    });

    test('phone is optional but must look like a number', () {
      expect(Validators.phone(''), isNull);
      expect(Validators.phone('+7 707 334 52 11'), isNull);
      expect(Validators.phone('12ab'), isNotNull);
    });

    test('amount and confirmPassword', () {
      expect(Validators.amount('abc'), isNotNull);
      expect(Validators.amount('-5'), isNotNull);
      expect(Validators.amount('1500'), isNull);
      expect(Validators.amount('50001'), isNotNull);
      expect(Validators.amount('50000'), isNull);
      expect(Validators.confirmPassword('a', 'b'), isNotNull);
      expect(Validators.confirmPassword('b', 'b'), isNull);
    });
  });

  group('Formatters', () {
    test('price', () {
      expect(Formatters.price(2500), '2 500 тг');
      expect(Formatters.price(1000, AppCurrency.rub), '190 ₽');
    });

    test('plural', () {
      expect(Formatters.plural(1, 'отзыв', 'отзыва', 'отзывов'), 'отзыв');
      expect(Formatters.plural(3, 'отзыв', 'отзыва', 'отзывов'), 'отзыва');
      expect(Formatters.plural(11, 'отзыв', 'отзыва', 'отзывов'), 'отзывов');
    });
  });
}
