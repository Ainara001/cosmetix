import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/database/catalog_data.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/features/virtual_makeup/virtual_makeup.dart';
import 'package:cosmetix/features/virtual_makeup/ui/virtual_makeup_controller.dart';
import 'package:cosmetix/repositories/try_on_repository.dart';

import 'screen_test.dart' show FakeLandmarks;
import 'synthetic_face.dart';

/// The cells of a palette in the try-on: a cell can be tried on only when its
/// colour is known, and then it is a try-on item of its own.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late CatalogData catalog;
  setUpAll(() async => catalog = await CatalogData.load());
  int idOf(String name) =>
      catalog.products.indexWhere((p) => p.name == name) + 1;
  final p02 = 'Better Than Palette 02 Mahogany Garden';

  Future<DatabaseHelper> db() async {
    final h = DatabaseHelper(path: inMemoryDatabasePath);
    await h.database;
    addTearDown(h.close);
    return h;
  }

  Future<void> measure(DatabaseHelper h, int position, int colour) async {
    final d = await h.database;
    await d.update(
      'product_shade_pans',
      {
        'colour': colour,
        'colour_status': 'measured_swatch',
        'colour_source': 'test measurement',
        'measurement_ref': 'test-$position',
      },
      where: 'pan_key = ?',
      whereArgs: [
        'romand-better-than-palette/02/${position.toString().padLeft(2, '0')}',
      ],
    );
  }

  test('with no measured cell the palette cannot be tried on', () async {
    final h = await db();
    final item = (await TryOnRepository(h).item(idOf(p02)))!;
    expect(item.canTryOn, isFalse);
    expect(item.panKey, isNull);
    expect(await TryOnRepository(h).sameLine(item), isEmpty);
  });

  test('a measured cell is offered, and only that one', () async {
    final h = await db();
    await measure(h, 3, 0xFF8A4B3C);
    final repo = TryOnRepository(h);
    final item = (await repo.item(idOf(p02)))!;
    expect(item.canTryOn, isTrue);
    expect(item.panKey, 'romand-better-than-palette/02/03');
    expect(item.panPosition, 3);
    expect(item.colour, const Color(0xFF8A4B3C));
    expect(item.status, 'measured_swatch');
    expect(item.isApproximate, isFalse);
    expect(item.productId, idOf(p02), reason: 'still the palette product');
    // one measured cell is not a choice
    expect(await repo.sameLine(item), isEmpty);
  });

  test('several measured cells are the choice, each with its colour', () async {
    final h = await db();
    await measure(h, 3, 0xFF8A4B3C);
    await measure(h, 7, 0xFF4B2E2A);
    final repo = TryOnRepository(h);
    final item = (await repo.item(idOf(p02)))!;
    final cells = await repo.sameLine(item);
    expect(cells.map((c) => c.panPosition), [3, 7]);
    expect(cells.map((c) => c.colour), [
      const Color(0xFF8A4B3C),
      const Color(0xFF4B2E2A),
    ]);
    expect(cells.every((c) => c.productId == idOf(p02)), isTrue);
    // two cells of one palette are two different items
    expect(cells[0] == cells[1], isFalse);
    expect(cells[0] == cells[0], isTrue);
  });

  test('a lipstick is not affected', () async {
    final h = await db();
    await measure(h, 3, 0xFF8A4B3C);
    final berry = idOf('Ink Mood Glowy Tint 30 Happy Berry');
    final item = (await TryOnRepository(h).item(berry))!;
    expect(item.panKey, isNull);
    expect(item.status, 'legacy_estimate');
    expect(item.isApproximate, isTrue);
  });

  test(
    'the palette is still not listed among products with a known colour',
    () async {
      final h = await db();
      await measure(h, 3, 0xFF8A4B3C);
      // the list of eyeshadow products is made of whole products with a colour at
      // product level; a palette gets there only through its cells (see above)
      final all = await TryOnRepository(h).all(MakeupZone.eyeshadow);
      expect(all.where((i) => i.productId == idOf(p02)), isEmpty);
    },
  );

  testWidgets('the controller starts with a measured cell and switches cells', (
    t,
  ) async {
    final face = SyntheticFace.build();
    final h = DatabaseHelper(path: inMemoryDatabasePath);
    await t.runAsync(() async {
      await h.database;
      await measure(h, 3, 0xFF8A4B3C);
      await measure(h, 7, 0xFF4B2E2A);
    });
    addTearDown(() => t.runAsync(h.close));
    final c = VirtualMakeupController(
      landmarks: FakeLandmarks([face.points]),
      catalog: TryOnRepository(h),
      debounce: Duration.zero,
    );
    addTearDown(c.dispose);
    expect(await t.runAsync(() => c.startWith(idOf(p02))), isTrue);
    expect(c.items[MakeupZone.eyeshadow]!.panPosition, 3);
    expect(c.look.eyeshadow.color, const Color(0xFF8A4B3C));
    expect(c.look.eyeshadow.enabled, isTrue);
    expect(c.lineShades.map((i) => i.panPosition), [3, 7]);
    await t.runAsync(() => c.applyItem(c.lineShades.last));
    expect(c.items[MakeupZone.eyeshadow]!.panPosition, 7);
    expect(c.look.eyeshadow.color, const Color(0xFF4B2E2A));
    expect(c.items.length, 1);
  });
}
