import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/core/theme/app_theme.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/repositories/product_repository.dart';
import 'package:cosmetix/widgets/product_kind_card.dart';

/// The classifier v2 on the product page: type, rinse-off, purpose and the
/// actives that stand high in the INCI list, shown separately.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DatabaseHelper h;
  late List<Product> all;
  setUp(() async {
    h = DatabaseHelper(path: inMemoryDatabasePath);
    await h.database;
    final db = await h.database;
    final user = await db.query('users', limit: 1);
    all = await ProductRepository(h).getAll(user.isEmpty ? 1 : user.first['id']! as int);
  });
  tearDown(() => h.close());

  Future<void> pump(WidgetTester t, Product p) => t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: ProductKindCard(product: p)),
    ),
  );

  Product named(String n) => all.firstWhere((p) => p.name == n);

  testWidgets('a cleanser is shown as rinse-off cleansing', (t) async {
    await t.runAsync(() async {});
    await pump(t, named('Low pH Good Morning Gel Cleanser'));
    expect(find.textContaining('Очищающее средство'), findsOneWidget);
    expect(find.textContaining('смывается'), findsOneWidget);
    expect(find.textContaining('Очищение'), findsOneWidget);
    // an automatic label says so
    expect(find.textContaining('автоматически'), findsOneWidget);
  });

  testWidgets('a cream stays on the skin and is not a cleanser', (t) async {
    await pump(t, named('Moisturizing Cream'));
    expect(find.textContaining('остаётся на коже'), findsOneWidget);
    expect(find.textContaining('смывается'), findsNothing);
  });

  testWidgets('an acid product shows exfoliation and the acid near the top', (t) async {
    await pump(t, named('BHA Blackhead Power Liquid'));
    expect(find.textContaining('Отшелушивание'), findsOneWidget);
    expect(find.textContaining('В начале состава'), findsOneWidget);
  });

  testWidgets('a product the rules cannot place says it waits for review', (t) async {
    await pump(t, named('Retinol 0.5% in Squalane'));
    expect(find.byKey(const Key('product-kind-review')), findsOneWidget);
  });

  testWidgets('makeup, perfume and the gift set get no card', (t) async {
    final makeup = all.firstWhere((p) => p.category == 'Макияж');
    expect(ProductKindCard.applies(makeup), isFalse);
    await pump(t, makeup);
    expect(find.byKey(const Key('product-kind-card')), findsNothing);
  });
}
