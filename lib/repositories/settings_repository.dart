import 'package:sqflite/sqflite.dart';

import 'package:cosmetix/database/database_helper.dart';

class SettingsRepository {
  SettingsRepository(this._helper);

  final DatabaseHelper _helper;

  Future<Map<String, String>> all() async {
    final db = await _helper.database;
    final rows = await db.query('settings');
    return {for (final r in rows) r['key'] as String: r['value'] as String};
  }

  Future<void> set(String key, String value) async {
    final db = await _helper.database;
    await db.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
