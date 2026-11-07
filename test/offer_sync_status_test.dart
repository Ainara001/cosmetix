import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/core/theme/app_theme.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/providers/offer_sync_provider.dart';
import 'package:cosmetix/repositories/offer_sync_repository.dart';
import 'package:cosmetix/services/ai/ai_config.dart';
import 'package:cosmetix/services/offer_sync_service.dart';
import 'package:cosmetix/services/server/server_http.dart';
import 'package:cosmetix/widgets/offer_sync_status.dart';

/// The line under the prices: not connected / never loaded / updated on a date /
/// could not update (the saved prices stay).
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late DatabaseHelper h;
  late OfferSyncRepository repo;
  setUp(() async {
    h = DatabaseHelper(path: inMemoryDatabasePath);
    await h.database;
    repo = OfferSyncRepository(h);
  });
  tearDown(() => h.close());

  OfferSyncProvider provider(String baseUrl) {
    final cfg = AiConfig(baseUrl: baseUrl);
    return OfferSyncProvider(
      OfferSyncService(
        ServerHttp(
          () => cfg,
          retry: RetryPolicy.none,
          timeout: const Duration(seconds: 2),
        ),
        repo,
        configured: () => cfg.isConfigured,
      ),
      repo,
      configured: () => cfg.isConfigured,
    );
  }

  Future<void> pump(WidgetTester t, OfferSyncProvider p) => t.pumpWidget(
    ChangeNotifierProvider.value(
      value: p,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: OfferSyncStatus()),
      ),
    ),
  );

  testWidgets('no server address: says so and offers no refresh', (t) async {
    await pump(t, provider(''));
    expect(find.text('Сервер цен не подключён.'), findsOneWidget);
    expect(find.byKey(const Key('offer-sync-refresh')), findsNothing);
  });

  testWidgets('a server is set but nothing was loaded yet', (t) async {
    await pump(t, provider('http://127.0.0.1:1'));
    expect(find.text('Цены с сервера ещё не загружались.'), findsOneWidget);
    expect(find.byKey(const Key('offer-sync-refresh')), findsOneWidget);
  });

  testWidgets('the date of the last good copy is shown', (t) async {
    await t.runAsync(
      () => repo.remember(
        OfferSyncRepository.keySyncedAt,
        DateTime(2026, 11, 5).millisecondsSinceEpoch.toString(),
      ),
    );
    final p = provider('http://127.0.0.1:1');
    await t.runAsync(p.load);
    await pump(t, p);
    expect(find.text('Цены обновлены: 05.11.2026'), findsOneWidget);
  });

  testWidgets('a failed refresh says so and keeps the old date', (t) async {
    await t.runAsync(
      () => repo.remember(
        OfferSyncRepository.keySyncedAt,
        DateTime(2026, 11, 5).millisecondsSinceEpoch.toString(),
      ),
    );
    final p = provider('http://127.0.0.1:1'); // nothing listens there
    await t.runAsync(p.load);
    await pump(t, p);
    await t.tap(find.byKey(const Key('offer-sync-refresh')));
    await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await t.pump();
    expect(
      find.text(
        'Не удалось обновить цены. Показаны сохранённые, с датой проверки.',
      ),
      findsOneWidget,
    );
    expect(p.lastSyncedAt, DateTime(2026, 11, 5));
  });

  testWidgets('without the provider the widget draws nothing', (t) async {
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: OfferSyncStatus()),
      ),
    );
    expect(find.byKey(const Key('offer-sync-status')), findsNothing);
  });
}
