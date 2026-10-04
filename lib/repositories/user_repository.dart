import 'package:sqflite/sqflite.dart';

import 'package:cosmetix/core/utils/password_hasher.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/database/seed_data.dart';
import 'package:cosmetix/models/app_user.dart';

class UserRepository {
  UserRepository(this._helper);

  final DatabaseHelper _helper;

  static const _sessionKey = 'current_user_id';

  Future<int?> currentUserId() async {
    final db = await _helper.database;
    final rows = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [_sessionKey],
    );
    if (rows.isEmpty) return null;
    return int.tryParse(rows.first['value'] as String);
  }

  Future<void> setCurrentUser(int? id) async {
    final db = await _helper.database;
    if (id == null) {
      await db.delete('settings', where: 'key = ?', whereArgs: [_sessionKey]);
    } else {
      await db.insert('settings', {
        'key': _sessionKey,
        'value': '$id',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<AppUser?> getById(int id) async {
    final db = await _helper.database;
    final rows = await db.query('users', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : AppUser.fromMap(rows.first);
  }

  Future<bool> emailExists(String email, {int? exceptId}) async {
    final db = await _helper.database;
    final rows = await db.query(
      'users',
      columns: ['id'],
      where: exceptId == null
          ? 'LOWER(email) = ?'
          : 'LOWER(email) = ? AND id != ?',
      whereArgs: [email.trim().toLowerCase(), ?exceptId],
    );
    return rows.isNotEmpty;
  }

  /// Returns null if the e-mail/password pair is wrong.
  Future<AppUser?> login(String email, String password) async {
    final db = await _helper.database;
    final rows = await db.query(
      'users',
      where: 'LOWER(email) = ? AND password_hash = ?',
      whereArgs: [email.trim().toLowerCase(), PasswordHasher.hash(password)],
    );
    return rows.isEmpty ? null : AppUser.fromMap(rows.first);
  }

  /// Throws [StateError] when the e-mail is already used.
  Future<AppUser> register({
    required String firstName,
    required String email,
    required String password,
    String lastName = '',
  }) async {
    if (await emailExists(email)) {
      throw StateError('Пользователь с таким email уже существует');
    }
    final db = await _helper.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await db.transaction((txn) async {
      final id = await txn.insert('users', {
        'first_name': firstName.trim(),
        'last_name': lastName.trim(),
        'email': email.trim().toLowerCase(),
        'password_hash': PasswordHasher.hash(password),
        'created_at': now,
        'updated_at': now,
      });
      await SeedData.insertUserDefaults(txn, id);
      return id;
    });
    return (await getById(id))!;
  }

  Future<void> updateProfile({
    required int id,
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String city,
    int? avatarColor,
  }) async {
    final db = await _helper.database;
    await db.update(
      'users',
      {
        'avatar_color': ?avatarColor,
        'first_name': firstName.trim(),
        'last_name': lastName.trim(),
        'email': email.trim().toLowerCase(),
        'phone': phone.trim(),
        'city': city.trim(),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateBeauty(
    int id, {
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
    final db = await _helper.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final values = <String, Object?>{
      'beauty_source': ?source,
      'beauty_confidence': ?confidence,
      if (clearConfidence) 'beauty_confidence': null,
      if (confidence != null) 'beauty_analyzed_at': now,
      if (markCompleted) 'beauty_completed_at': now,
      'skin_type': ?skinType,
      'skin_tone': ?skinTone,
      'undertone': ?undertone,
      'color_type': ?colorType,
      if (skinConcerns != null) 'skin_concerns': skinConcerns.join('|'),
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    };
    await db.update('users', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> setAvatarPath(int id, String? path) async {
    final db = await _helper.database;
    await db.update(
      'users',
      {
        'avatar_path': path,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<bool> changePassword(String email, String newPassword) async {
    final db = await _helper.database;
    final n = await db.update(
      'users',
      {
        'password_hash': PasswordHasher.hash(newPassword),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'LOWER(email) = ?',
      whereArgs: [email.trim().toLowerCase()],
    );
    return n > 0;
  }

  Future<void> incrementVisits(int id) async {
    final db = await _helper.database;
    await db.rawUpdate('UPDATE users SET visits = visits + 1 WHERE id = ?', [
      id,
    ]);
  }

  Future<void> addBonus(int id, int bonus) async {
    final db = await _helper.database;
    await db.rawUpdate(
      'UPDATE users SET bonus_points = bonus_points + ? WHERE id = ?',
      [bonus, id],
    );
  }
}
