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
      return e.message;
    } catch (_) {
      return tr('Не удалось создать аккаунт. Попробуйте ещё раз');
    }
  }

  /// Local imitation of Google / Apple sign in: a local account is created
  /// (or reused) so the whole flow works without a server.
  Future<String?> socialLogin(String provider) async {
    try {
      final email = '${provider.toLowerCase()}.user@cosmetix.local';
      var user = await _users.login(email, 'social-$provider');
      user ??= await _users.register(
        firstName: provider,
        lastName: tr('Пользователь'),
        email: email,
        password: 'social-$provider',
      );
      await _start(user);
      return null;
    } catch (_) {
      return trf('Не удалось войти через {provider}', {'provider': provider});
    }
  }

  Future<bool> emailExists(String email) => _users.emailExists(email);

  Future<bool> resetPassword(String email, String newPassword) =>
      _users.changePassword(email, newPassword);

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
  }) async {
    if (_user == null) return;
    await _users.updateBeauty(
      _user!.id,
      skinType: skinType,
      skinTone: skinTone,
      undertone: undertone,
      colorType: colorType,
      skinConcerns: skinConcerns,
    );
    await reload();
  }
}
