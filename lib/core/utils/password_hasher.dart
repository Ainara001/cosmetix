import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Password hashing: PBKDF2-HMAC-SHA256 with a random salt per password.
///
/// Stored format: `pbkdf2$<iterations>$<salt base64>$<hash base64>`.
/// Passwords saved by older builds (one shared salt, one SHA-256 pass) still
/// verify and are upgraded on the next successful sign in
/// (see [needsUpgrade]).
class PasswordHasher {
  PasswordHasher._();

  static const _legacySalt = 'cosmetix.local.v1';
  static const _prefix = 'pbkdf2';
  static const iterations = 10000;
  static const _saltBytes = 16;
  static const _keyBytes = 32;

  /// Marks accounts created through the local Google / Apple imitation: no
  /// password can ever match it, so these accounts cannot be opened from the
  /// e-mail + password form.
  static const unusable = '!no-password';

  static String hash(String password, {Random? random}) {
    final rnd = random ?? Random.secure();
    final salt = Uint8List.fromList([
      for (var i = 0; i < _saltBytes; i++) rnd.nextInt(256),
    ]);
    final key = _pbkdf2(utf8.encode(password), salt, iterations);
    return '$_prefix\$$iterations\$${base64.encode(salt)}\$${base64.encode(key)}';
  }

  /// Same as [hash] but off the UI thread (about 0.1-0.5 s of CPU).
  static Future<String> hashAsync(String password) =>
      Isolate.run(() => hash(password));

  /// Same as [verify] but off the UI thread.
  static Future<bool> verifyAsync(String password, String stored) =>
      stored == unusable || !stored.startsWith('$_prefix\$')
      ? Future.value(verify(password, stored)) // legacy / unusable: instant
      : Isolate.run(() => verify(password, stored));

  static bool verify(String password, String stored) {
    if (stored == unusable) return false;
    if (!stored.startsWith('$_prefix\$')) {
      return _constantTimeEquals(_legacyHash(password), stored);
    }
    final parts = stored.split('\$');
    if (parts.length != 4) return false;
    final rounds = int.tryParse(parts[1]);
    if (rounds == null || rounds < 1) return false;
    try {
      final salt = base64.decode(parts[2]);
      final expected = base64.decode(parts[3]);
      final actual = _pbkdf2(utf8.encode(password), salt, rounds);
      return _constantTimeEquals(
        base64.encode(actual),
        base64.encode(expected),
      );
    } on FormatException {
      return false;
    }
  }

  /// True for hashes written by older builds or with fewer iterations.
  static bool needsUpgrade(String stored) {
    if (stored == unusable) return false;
    if (!stored.startsWith('$_prefix\$')) return true;
    final rounds = int.tryParse(stored.split('\$')[1]) ?? 0;
    return rounds < iterations;
  }

  static String _legacyHash(String password) =>
      sha256.convert(utf8.encode('$_legacySalt:$password')).toString();

  static Uint8List _pbkdf2(List<int> password, List<int> salt, int rounds) {
    final hmac = Hmac(sha256, password);
    final out = BytesBuilder();
    final blocks = (_keyBytes / 32).ceil();
    for (var block = 1; block <= blocks; block++) {
      var u = hmac.convert([
        ...salt,
        (block >> 24) & 0xff,
        (block >> 16) & 0xff,
        (block >> 8) & 0xff,
        block & 0xff,
      ]).bytes;
      final t = List<int>.from(u);
      for (var i = 1; i < rounds; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      out.add(t);
    }
    return Uint8List.fromList(out.toBytes().sublist(0, _keyBytes));
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
