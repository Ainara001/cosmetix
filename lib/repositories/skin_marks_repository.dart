import 'package:cosmetix/core/face/face_zones.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/models/skin_marks.dart';

/// The person's marks on the face zones. Stored on the phone only.
class SkinMarksRepository {
  SkinMarksRepository(this._helper);

  final DatabaseHelper _helper;

  Future<SkinMarks> current(int userId) async {
    final db = await _helper.database;
    final rows = await db.query(
      'skin_zone_marks',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    final marks = <SkinZoneMark>{};
    int? at;
    for (final r in rows) {
      final z = FaceZone.fromCode(r['zone'] as String?);
      final f = SkinFeature.fromCode(r['feature'] as String?);
      if (z == null || f == null) continue;
      marks.add(SkinZoneMark(z, f));
      final t = r['marked_at'] as int;
      if (at == null || t > at) at = t;
    }
    return SkinMarks(
      marks,
      markedAt: at == null ? null : DateTime.fromMillisecondsSinceEpoch(at),
    );
  }

  /// Replaces all marks of the person (all or nothing).
  Future<void> replace(int userId, Set<SkinZoneMark> marks) async {
    final db = await _helper.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.delete(
        'skin_zone_marks',
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      for (final m in marks) {
        await txn.insert('skin_zone_marks', {
          'user_id': userId,
          'zone': m.zone.code,
          'feature': m.feature.code,
          'marked_at': now,
        });
      }
    });
  }
}
