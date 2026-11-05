import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cosmetix/database/catalog_data.dart';

/// The rights audit of the product photos (tools/rights) must describe exactly
/// the photos that ship, and must never call a photo "cleared" without a
/// recorded licence or permission.
void main() {
  final manifest =
      jsonDecode(File('tools/rights/photo_rights.json').readAsStringSync())
          as Map<String, Object?>;
  final rows = [
    for (final r in manifest['products']! as List)
      (r as Map).cast<String, Object?>(),
  ];

  test('the audit lists every product photo that is in the project', () {
    final listed = {for (final r in rows) r['file']! as String};
    final real = {
      for (final f in Directory('assets/products').listSync())
        if (f.path.endsWith('.jpg')) f.path,
    };
    expect(
      listed,
      real,
      reason: 'rerun python3 -I tools/rights/photo_audit.py',
    );
  });

  test('every photo a catalog product uses has an audit row', () async {
    final catalog = await CatalogData.load();
    final listed = {for (final r in rows) r['file']! as String};
    for (final p in catalog.products) {
      if (p.photo != null) {
        expect(listed, contains(p.photo), reason: p.name);
      }
    }
  });

  test('a photo is "cleared" only with its evidence recorded', () {
    for (final r in rows) {
      final status = r['rights_status'];
      expect(
        ['not_cleared', 'cleared'],
        contains(status),
        reason: '${r['file']}',
      );
      if (status == 'cleared') {
        expect(r['evidence'], isNotNull, reason: '${r['file']}');
        expect(r['licence_recorded'], isNot('none'), reason: '${r['file']}');
      } else {
        expect(r['share_build'], 'excluded', reason: '${r['file']}');
      }
    }
  });

  test('the generic photos of assets/photos are all accounted for', () {
    final listed = {
      for (final g in manifest['generic_photos']! as List)
        (g as Map)['file'] as String,
    };
    final real = {
      for (final f in Directory('assets/photos').listSync())
        if (f.path.endsWith('.jpg')) f.path,
    };
    expect(listed, real);
  });

  test('the share build script exists and is executable', () {
    final f = File('tools/rights/share_build.sh');
    expect(f.existsSync(), isTrue);
    expect(f.statSync().mode & 0x40, isNot(0), reason: 'chmod +x');
  });
}
