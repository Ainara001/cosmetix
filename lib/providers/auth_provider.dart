import 'dart:math';

import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/foundation.dart';

import 'package:cosmetix/models/app_user.dart';
import 'package:cosmetix/repositories/user_repository.dart';

/// Current user, sign in / sign up and the profile data.
class AuthProvider extends ChangeNotifier {
  AuthProvider(this._users);

  final UserRepository _users;

  AppUser? _user;
  AppUser? get user => _user;
  bool get isLoggedIn => _user != null;
  int get userId => _user!.id;

  /// Restores the saved session on app start.
  Future<void> restoreSession() async {
    try {
      final id = await _users.currentUserId();
      if (id != null) {
        _user = await _users.getById(id);
        if (_user != null) {
          await _users.incrementVisits(id);
          _user = await _users.getById(id);
        }
      }
    } catch (e) {
      debugPrint('restoreSession failed: $e');
      _user = null;
    }
    notifyListeners();
  }

  Future<void> _start(AppUser user) async {
    await _users.setCurrentUser(user.id);
    await _users.incrementVisits(user.id);
    _user = await _users.getById(user.id);
    notifyListeners();
  }

  /// Returns an error message or null on success.
  Future<String?> login(String email, String password) async {
    try {
      final user = await _users.login(email, password);
      if (user == null) return tr('Неверный email или пароль');
      await _start(user);
      return null;
    } catch (_) {
      return tr('Не удалось выполнить вход. Попробуйте ещё раз');
    }
  }

  Future<String?> register(String name, String email, String password) async {
    try {
      final user = await _users.register(
        firstName: name,
        email: email,
        password: password,
      );
      await _start(user);
      return null;
    } on StateError catch (e) {
      return tr(e.message);
    } catch (_) {
      return tr('Не удалось создать аккаунт. Попробуйте ещё раз');
    }
  }

  /// Local imitation of Google / Apple sign in: a local account without a
  /// usable password is created (or reused), so the whole flow works without a
  /// server and the account cannot be opened from the e-mail form.
  Future<String?> socialLogin(String provider) async {
    try {
      final user = await _users.socialUser(
        provider: provider,
        email: '${provider.toLowerCase()}.user@cosmetix.local',
        firstName: provider,
        lastName: tr('Пользователь'),
      );
      if (user == null) {
        return trf('Не удалось войти через {provider}', {'provider': provider});
      }
      await _start(user);
      return null;
    } catch (_) {
      return trf('Не удалось войти через {provider}', {'provider': provider});
    }
  }

  // ---- password reset (simulated e-mail) ----

  static const _resetTtl = Duration(minutes: 10);
  static const _resetMaxAttempts = 5;
  final Map<String, _ResetCode> _resetCodes = {};

  /// Creates the 6-digit code that the simulated "e-mail" shows. Always
  /// returns a code, so the screen never reveals whether the e-mail is
  /// registered; the code only works for an existing account.
  Future<String> requestResetCode(String email) async {
    final code = (100000 + Random.secure().nextInt(900000)).toString();
    final key = email.trim().toLowerCase();
    if (await _users.emailExists(key)) {
      _resetCodes[key] = _ResetCode(code, DateTime.now().add(_resetTtl));
    } else {
      _resetCodes.remove(key);
    }
    return code;
  }

  /// Changes the password when [code] matches the one issued for [email].
  /// Returns an error message or null on success.
  Future<String?> resetPassword(
    String email,
    String code,
    String newPassword,
  ) async {
    final key = email.trim().toLowerCase();
    final issued = _resetCodes[key];
    if (issued == null || DateTime.now().isAfter(issued.expires)) {
      _resetCodes.remove(key);
      return tr('Код устарел. Запросите новый');
    }
    if (issued.code != code.trim()) {
      issued.attempts++;
      if (issued.attempts >= _resetMaxAttempts) _resetCodes.remove(key);
      return tr('Неверный код');
    }
    _resetCodes.remove(key);
    try {
      final ok = await _users.changePassword(key, newPassword);
      return ok ? null : tr('Не удалось изменить пароль');
    } catch (_) {
      return tr('Не удалось изменить пароль');
    }
  }

  Future<void> logout() async {
    await _users.setCurrentUser(null);
    _user = null;
    notifyListeners();
  }

  Future<void> reload() async {
    if (_user == null) return;
    _user = await _users.getById(_user!.id);
    notifyListeners();
  }

  /// Returns an error message or null on success.
  Future<String?> updateProfile({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String city,
    int? avatarColor,
  }) async {
    if (_user == null) return tr('Вы не авторизованы');
    try {
      if (await _users.emailExists(email, exceptId: _user!.id)) {
        return tr('Этот email уже используется другим аккаунтом');
      }
      await _users.updateProfile(
        id: _user!.id,
        firstName: firstName,
        lastName: lastName,
        email: email,
        phone: phone,
        city: city,
        avatarColor: avatarColor,
      );
      await reload();
      return null;
    } catch (_) {
      return tr('Не удалось сохранить изменения');
    }
  }

  Future<void> updateBeauty({
    String? skinType,
    String? skinTone,
    String? undertone,
    String? colorType,
    List<String>? skinConcerns,
    String? source,
    double? confidence,
    bool clearConfidence = false,
    bool markCompleted = false,
  }) async {
    if (_user == null) return;
    await _users.updateBeauty(
      _user!.id,
      skinType: skinType,
      skinTone: skinTone,
      undertone: undertone,
      colorType: colorType,
      skinConcerns: skinConcerns,
      source: source,
      confidence: confidence,
      clearConfidence: clearConfidence,
      markCompleted: markCompleted,
    );
    await reload();
  }

  Future<void> updatePreferences({
    Set<String>? preferences,
    bool? useHistory,
  }) async {
    if (_user == null) return;
    await _users.updatePreferences(
      _user!.id,
      preferences: preferences,
      useHistory: useHistory,
    );
    await reload();
  }

  Future<void> setAvatarPath(String? path) async {
    if (_user == null) return;
    await _users.setAvatarPath(_user!.id, path);
    await reload();
  }
}

class _ResetCode {
  _ResetCode(this.code, this.expires);

  final String code;
  final DateTime expires;
  int attempts = 0;
}
