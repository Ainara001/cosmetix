import 'dart:convert';

import 'package:crypto/crypto.dart';

class PasswordHasher {
  PasswordHasher._();

  static const _salt = 'cosmetix.local.v1';

  static String hash(String password) =>
      sha256.convert(utf8.encode('$_salt:$password')).toString();
}
