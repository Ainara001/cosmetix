import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/models/app_user.dart';
import 'package:cosmetix/models/safety_models.dart';
import 'package:cosmetix/repositories/settings_repository.dart';
import 'package:cosmetix/services/ai/ai_config.dart';
import 'package:cosmetix/services/server/app_events.dart';
import 'package:cosmetix/services/server/cosmetix_server.dart';
import 'package:cosmetix/services/server/server_consent.dart';
import 'package:cosmetix/services/server/server_exceptions.dart';
import 'package:cosmetix/services/server/server_http.dart';
import 'package:cosmetix/services/server/sync_payloads.dart';

/// One request the fake server saw.
class Seen {
  Seen(this.method, this.path, this.query, this.headers, this.body);
  final String method;
  final String path;
  final Map<String, String> query;
  final Map<String, String> headers;
  final String body;

  Object? get json => body.isEmpty ? null : jsonDecode(body);
}

/// A scripted answer.
class Say {
  const Say(this.status, [this.body, this.headers = const {}, this.delay]);
  final int status;
  final Object? body; // Map/List -> JSON, String -> as is
  final Map<String, String> headers;
  final Duration? delay;
}

/// A tiny fake Cosmetix server on the loopback interface. Answers come from a
/// queue per "METHOD /path"; when the queue is empty the default is used.
class FakeServer {
  FakeServer._(this._server);

  final HttpServer _server;
  final seen = <Seen>[];
  final _queues = <String, List<Say>>{};
  final _defaults = <String, Say>{};

  static Future<FakeServer> start() async {
    final s = FakeServer._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    s._server.listen(s._handle);
    return s;
  }

  String get url => 'http://127.0.0.1:${_server.port}';

  /// The next answers for [route] ("GET /v1/catalog/products"), in order.
  void queue(String route, List<Say> answers) =>
      _queues.putIfAbsent(route, () => []).addAll(answers);

  void otherwise(String route, Say answer) => _defaults[route] = answer;

  Iterable<Seen> to(String route) =>
      seen.where((r) => '${r.method} ${r.path}' == route);

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    final body = await utf8.decoder.bind(req).join();
    final headers = <String, String>{};
    req.headers.forEach((k, v) => headers[k] = v.join(','));
    final rec = Seen(
      req.method,
      req.uri.path,
      Map.of(req.uri.queryParameters),
      headers,
      body,
    );
    seen.add(rec);
    final route = '${req.method} ${req.uri.path}';
    final q = _queues[route];
    final say = (q != null && q.isNotEmpty)
        ? q.removeAt(0)
        : (_defaults[route] ?? const Say(200, {}));
    if (say.delay != null) await Future<void>.delayed(say.delay!);
    try {
      req.response.statusCode = say.status;
      say.headers.forEach(req.response.headers.set);
      if (say.body != null) {
        req.response.headers.contentType = ContentType.json;
        req.response.write(
          say.body is String ? say.body : jsonEncode(say.body),
        );
      }
      await req.response.close();
    } catch (_) {
      // the client gave up (timeout test)
    }
  }
}

Map<String, Object?> productJson(int id, {String? country}) => {
  'id': id,
  'brand': 'Brand',
  'category': 'Макияж',
  'name': 'Product $id',
  'zone': 'Глаза',
  'price': 2500,
  'priceSource': 'demo',
  'oldPrice': null,
  'inStock': true,
  'art': 'tube',
  'color': 4294227650,
  'shade': null,
  'description': 'd',
  'naturalPercent': 90,
  'featured': false,
  'trending': true,
  'inci': 'Aqua, Glycerin',
  'sourceUrl': 'https://example.test/p$id',
  'country': country,
  'createdAt': '2026-11-01T10:00:00.000Z',
  'updatedAt': '2026-11-02T10:00:00.000Z',
};

Map<String, Object?> pageJson(
  List<int> ids, {
  required int total,
  int offset = 0,
}) => {
  'items': [for (final i in ids) productJson(i)],
  'total': total,
  'limit': 2,
  'offset': offset,
};

const _allScopes = {
  ShareScope.deviceRegistration,
  ShareScope.usageEvents,
  ShareScope.profile,
  ShareScope.reactions,
};

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late FakeServer fake;
  late MemoryServerStateStore store;
  late List<Duration> sleeps;
  late CosmetixServer api;

  CosmetixServer build({
    Duration timeout = const Duration(seconds: 5),
    RetryPolicy retry = const RetryPolicy(),
    String? baseUrl,
  }) => CosmetixServer(
    config: () => AiConfig(baseUrl: baseUrl ?? fake.url),
    store: store,
    http: ServerHttp(
      () => AiConfig(baseUrl: baseUrl ?? fake.url),
      timeout: timeout,
      retry: retry,
      sleep: (d) async => sleeps.add(d),
    ),
    now: () => DateTime.utc(2026, 11, 4, 12),
  );

  setUp(() async {
    fake = await FakeServer.start();
    store = MemoryServerStateStore();
    sleeps = [];
    api = build();
  });
  tearDown(() => fake.close());

  Future<void> allowAll() => api.setConsent(_allScopes);
  Future<void> registered() async {
    fake.otherwise(
      'POST /v1/devices',
      const Say(201, {'userId': 'u-1', 'token': 'secret-token-value'}),
    );
    await allowAll();
    await api.registerDevice();
  }

  group('catalog (no consent needed, no user data sent)', () {
    test('pages are followed until the total is reached', () async {
      fake.queue('GET /v1/catalog/products', [
        Say(200, pageJson([1, 2], total: 3)),
        Say(200, pageJson([3], total: 3, offset: 2)),
      ]);
      final all = await api.fetchCatalog(pageSize: 2);
      expect(all.map((p) => p.id), [1, 2, 3]);
      final reqs = fake.to('GET /v1/catalog/products').toList();
      expect(reqs.map((r) => r.query['offset']), ['0', '2']);
      expect(reqs.every((r) => r.query['limit'] == '2'), isTrue);
      // a public read: no token, no body, no identity
      for (final r in reqs) {
        expect(r.headers.containsKey('authorization'), isFalse);
        expect(r.body, isEmpty);
      }
      expect(store.credentials, isNull);
    });

    test('updatedSince is sent as UTC ISO time', () async {
      fake.otherwise(
        'GET /v1/catalog/products',
        Say(200, pageJson([], total: 0)),
      );
      await api.fetchCatalogPage(updatedSince: DateTime.utc(2026, 11, 1, 5));
      expect(
        fake.seen.single.query['updatedSince'],
        '2026-11-01T05:00:00.000Z',
      );
    });

    test('the shared app token goes as a header when configured', () async {
      fake.otherwise(
        'GET /v1/catalog/products',
        Say(200, pageJson([], total: 0)),
      );
      final a = CosmetixServer(
        config: () => AiConfig(baseUrl: fake.url, appToken: 'shared'),
        store: store,
      );
      await a.fetchCatalogPage();
      expect(fake.seen.single.headers['x-app-token'], 'shared');
    });

    test(
      'a product keeps the demo-price flag and an unknown country',
      () async {
        fake.queue('GET /v1/catalog/products', [
          Say(200, pageJson([7], total: 1)),
        ]);
        final p = (await api.fetchCatalogPage()).items.single;
        expect(p.isDemoPrice, isTrue);
        expect(p.country, isNull);
        expect(p.updatedAt, DateTime.utc(2026, 11, 2, 10));
      },
    );

    test('details: ingredients, traits, offers with their source', () async {
      fake.queue('GET /v1/catalog/products/5', [
        Say(200, {
          ...productJson(5),
          'ingredients': [
            {'id': 1, 'name': 'Вода'},
            {'id': 4, 'name': 'Глицерин'},
          ],
          'traits': {
            'skinTypes': ['Сухая'],
            'tags': <String>[],
          },
          'prices': [
            {
              'storeId': 2,
              'price': 2700,
              'inStock': true,
              'qty': 3,
              'source': 'demo',
            },
          ],
        }),
      ]);
      final d = await api.fetchProduct(5);
      expect(d.ingredientIds, [1, 4]);
      expect(d.traits['skinTypes'], ['Сухая']);
      expect(d.offers.single.isDemo, isTrue);
      expect(d.product.id, 5);
    });

    test(
      'a wrong shape or text that is not JSON is ServerBadResponse',
      () async {
        fake.queue('GET /v1/catalog/products', [
          Say(200, {
            'items': [
              {...productJson(1), 'price': '2500'},
            ],
            'total': 1,
            'limit': 1,
            'offset': 0,
          }),
          const Say(200, 'not json at all'),
          const Say(200, {'total': 1}),
        ]);
        for (var i = 0; i < 3; i++) {
          await expectLater(
            api.fetchCatalogPage(),
            throwsA(isA<ServerBadResponse>()),
          );
        }
      },
    );

    test('a server that never ends is stopped', () async {
      fake.otherwise(
        'GET /v1/catalog/products',
        Say(200, pageJson([1, 2], total: 999)),
      );
      await expectLater(
        api.fetchCatalog(pageSize: 2, maxPages: 3),
        throwsA(isA<ServerBadResponse>()),
      );
      expect(fake.seen.length, 3);
    });

    test('a failing page throws and returns nothing partial', () async {
      fake.queue('GET /v1/catalog/products', [
        Say(200, pageJson([1, 2], total: 4)),
        const Say(400, {'error': 'bad_request', 'message': 'nope'}),
      ]);
      await expectLater(
        api.fetchCatalog(pageSize: 2),
        throwsA(isA<ServerRejected>()),
      );
    });
  });

  group('errors, timeouts and repeated requests', () {
    test('GET: 503 is repeated with growing pauses, then succeeds', () async {
      fake.queue('GET /v1/catalog/products', [
        const Say(503, {'error': 'x', 'message': 'busy'}),
        const Say(502),
        Say(200, pageJson([1], total: 1)),
      ]);
      final p = await api.fetchCatalogPage();
      expect(p.items.length, 1);
      expect(fake.seen.length, 3);
      expect(sleeps, [
        const Duration(milliseconds: 500),
        const Duration(milliseconds: 1000),
      ]);
    });

    test('GET: still 503 after all tries is ServerUnavailable', () async {
      fake.otherwise(
        'GET /v1/catalog/products',
        const Say(503, {'message': 'down'}),
      );
      await expectLater(
        api.fetchCatalogPage(),
        throwsA(
          isA<ServerUnavailable>().having((e) => e.message, 'message', 'down'),
        ),
      );
      expect(fake.seen.length, 3);
    });

    test('4xx is never repeated', () async {
      fake.otherwise(
        'GET /v1/catalog/products',
        const Say(400, {'error': 'bad_request', 'message': 'limit'}),
      );
      await expectLater(
        api.fetchCatalogPage(),
        throwsA(
          isA<ServerRejected>()
              .having((e) => e.statusCode, 'status', 400)
              .having((e) => e.code, 'code', 'bad_request'),
        ),
      );
      expect(fake.seen.length, 1);
      expect(sleeps, isEmpty);
    });

    test(
      '429 with a short Retry-After is waited out, even for a POST',
      () async {
        await allowAll();
        fake.queue('POST /v1/devices', [
          const Say(429, {'error': 'rate_limited'}, {'retry-after': '2'}),
          const Say(201, {'userId': 'u', 'token': 't-token'}),
        ]);
        final c = await api.registerDevice();
        expect(c.userId, 'u');
        expect(fake.seen.length, 2);
        expect(sleeps, [const Duration(seconds: 2)]);
      },
    );

    test('429 with a long Retry-After is reported at once', () async {
      fake.otherwise(
        'GET /v1/catalog/products',
        const Say(429, {'message': 'busy'}, {'retry-after': '900'}),
      );
      await expectLater(
        api.fetchCatalogPage(),
        throwsA(
          isA<ServerRateLimited>().having(
            (e) => e.retryAfter,
            'retryAfter',
            900,
          ),
        ),
      );
      expect(fake.seen.length, 1);
    });

    test('a slow server is ServerTimeout', () async {
      fake.otherwise(
        'GET /v1/catalog/products',
        Say(
          200,
          pageJson([], total: 0),
          const {},
          const Duration(milliseconds: 600),
        ),
      );
      final slow = build(
        timeout: const Duration(milliseconds: 120),
        retry: RetryPolicy.none,
      );
      await expectLater(slow.fetchCatalogPage(), throwsA(isA<ServerTimeout>()));
    });

    test('an unreachable server is ServerUnavailable (offline)', () async {
      final dead = await FakeServer.start();
      final url = dead.url;
      await dead.close();
      final offline = build(baseUrl: url);
      await expectLater(
        offline.fetchCatalogPage(),
        throwsA(isA<ServerUnavailable>()),
      );
      // GET is repeated: 3 tries, 2 pauses
      expect(sleeps.length, 2);
    });

    test('no address set: ServerUnavailable and no request', () async {
      final none = build(baseUrl: '');
      await expectLater(
        none.fetchCatalogPage(),
        throwsA(isA<ServerUnavailable>()),
      );
    });

    test('a redirect is not followed (tokens must not travel on)', () async {
      fake.otherwise(
        'GET /v1/catalog/products',
        const Say(302, null, {'location': 'http://127.0.0.1:1/steal'}),
      );
      await expectLater(api.fetchCatalogPage(), throwsA(isA<ServerRejected>()));
      expect(fake.seen.length, 1);
    });
  });

  group('consent', () {
    test(
      'everything about the user is refused until the user allows it',
      () async {
        final calls = <String, Future<Object?> Function()>{
          'register': api.registerDevice,
          'events': () => api.sendEvents([AppEvent.appOpen()]),
          'profile': () => api.pushProfile(const ProfileSyncPayload()),
          'reaction': () => api.pushReaction(
            const ReactionSyncPayload(
              clientId: '1',
              productId: 1,
              title: 't',
              severity: 2,
              date: '2026-01-01',
            ),
          ),
          'delete reaction': () => api.deleteReaction(1),
        };
        for (final e in calls.entries) {
          await expectLater(
            e.value(),
            throwsA(isA<ConsentRequired>()),
            reason: e.key,
          );
        }
        expect(fake.seen, isEmpty, reason: 'nothing may leave the phone');
      },
    );

    test('each scope opens only its own door', () async {
      fake.otherwise(
        'POST /v1/devices',
        const Say(201, {'userId': 'u', 'token': 'tok-en-12345'}),
      );
      await api.setConsent({ShareScope.deviceRegistration});
      await api.registerDevice();
      await expectLater(
        api.sendEvents([AppEvent.appOpen()]),
        throwsA(
          isA<ConsentRequired>().having(
            (e) => e.scope,
            'scope',
            ShareScope.usageEvents,
          ),
        ),
      );
      await expectLater(
        api.pushProfile(const ProfileSyncPayload()),
        throwsA(
          isA<ConsentRequired>().having(
            (e) => e.scope,
            'scope',
            ShareScope.profile,
          ),
        ),
      );
    });

    test('taking a scope back stops that sending at once', () async {
      await registered();
      fake.otherwise('POST /v1/events', const Say(201, {'accepted': 1}));
      expect((await api.sendEvents([AppEvent.appOpen()])).ok, isTrue);
      await api.setConsent({ShareScope.deviceRegistration});
      await expectLater(
        api.sendEvents([AppEvent.appOpen()]),
        throwsA(isA<ConsentRequired>()),
      );
      expect(fake.to('POST /v1/events').length, 1);
    });

    test('a consent from older rules counts as none', () async {
      final old = ServerConsent(
        version: ServerConsent.currentVersion - 1,
        scopes: _allScopes,
      );
      expect(old.allows(ShareScope.usageEvents), isFalse);
      store.consent = old;
      await expectLater(api.registerDevice(), throwsA(isA<ConsentRequired>()));
    });

    test('unreadable saved consent is "no consent", never "consent"', () {
      for (final junk in <Object?>[
        null,
        5,
        'x',
        [],
        {'scopes': 'all'},
        {'version': 1},
        {'version': 'a', 'scopes': []},
      ]) {
        expect(ServerConsent.fromJson(junk).scopes, isEmpty, reason: '$junk');
      }
      final back = ServerConsent.fromJson(
        ServerConsent(
          scopes: {ShareScope.profile},
          givenAt: DateTime.utc(2026),
        ).toJson(),
      );
      expect(back.allows(ShareScope.profile), isTrue);
      expect(back.allows(ShareScope.reactions), isFalse);
    });

    test('stored in the app settings table and read back', () async {
      final helper = DatabaseHelper(path: inMemoryDatabasePath);
      addTearDown(helper.close);
      final s = SettingsServerStateStore(SettingsRepository(helper));
      expect((await s.loadConsent()).scopes, isEmpty);
      expect(await s.loadCredentials(), isNull);
      await s.saveConsent(
        ServerConsent(scopes: _allScopes, givenAt: DateTime.utc(2026)),
      );
      await s.saveCredentials(const DeviceCredentials(userId: 'u', token: 't'));
      expect((await s.loadConsent()).allows(ShareScope.reactions), isTrue);
      expect((await s.loadCredentials())!.userId, 'u');
      await s.saveCredentials(null);
      expect(await s.loadCredentials(), isNull);
      // garbage in the table does not crash and does not grant anything
      await SettingsRepository(
        helper,
      ).set(SettingsServerStateStore.consentKey, '{{{');
      expect((await s.loadConsent()).scopes, isEmpty);
    });

    test('the token never shows in toString', () {
      expect(
        const DeviceCredentials(
          userId: 'u',
          token: 'secret-token-value',
        ).toString(),
        isNot(contains('secret-token-value')),
      );
    });
  });

  group('device registration (anonymous)', () {
    test('sends nothing about the person or the phone', () async {
      await registered();
      final r = fake.to('POST /v1/devices').single;
      expect(r.body, isEmpty);
      expect(r.headers.containsKey('authorization'), isFalse);
      // only the technical headers: no model, no os, no ids
      final extra = r.headers.keys.toSet().difference({
        'user-agent',
        'host',
        'content-length',
        'accept-encoding',
      });
      expect(extra, isEmpty, reason: 'unexpected headers: $extra');
      expect(r.headers['user-agent'], 'cosmetix-app');
      expect(store.credentials!.userId, 'u-1');
    });

    test(
      'registering again returns the stored identity, no second request',
      () async {
        await registered();
        final again = await api.registerDevice();
        expect(again.token, 'secret-token-value');
        expect(fake.to('POST /v1/devices').length, 1);
      },
    );

    test('parallel calls register once', () async {
      fake.otherwise(
        'POST /v1/devices',
        const Say(
          201,
          {'userId': 'u-1', 'token': 'tok-en-12345'},
          {},
          Duration(milliseconds: 50),
        ),
      );
      await allowAll();
      final all = await Future.wait([
        api.registerDevice(),
        api.registerDevice(),
        api.registerDevice(),
      ]);
      expect(all.map((c) => c.userId).toSet(), {'u-1'});
      expect(fake.to('POST /v1/devices').length, 1);
    });

    test('a POST is not repeated when the server says 503', () async {
      await allowAll();
      fake.otherwise('POST /v1/devices', const Say(503, {'message': 'down'}));
      await expectLater(
        api.registerDevice(),
        throwsA(isA<ServerUnavailable>()),
      );
      expect(fake.to('POST /v1/devices').length, 1);
      expect(store.credentials, isNull);
    });

    test('an incomplete answer stores nothing', () async {
      await allowAll();
      fake.otherwise('POST /v1/devices', const Say(201, {'userId': 'u'}));
      await expectLater(
        api.registerDevice(),
        throwsA(isA<ServerBadResponse>()),
      );
      expect(store.credentials, isNull);
    });
  });

  group('events', () {
    test('need a registered device', () async {
      await allowAll();
      await expectLater(
        api.sendEvents([AppEvent.appOpen()]),
        throwsA(isA<DeviceNotRegistered>()),
      );
    });

    test('only the allowed shape: type, fixed props, time', () async {
      await registered();
      fake.otherwise('POST /v1/events', const Say(201, {'accepted': 4}));
      final at = DateTime.utc(2026, 11, 4, 9);
      final res = await api.sendEvents([
        AppEvent.appOpen(at: at),
        AppEvent.screenView('product_page', at: at),
        AppEvent.productView(12, at: at),
        AppEvent.productFavorited(12, favorited: true, at: at),
      ]);
      expect(res.ok, isTrue);
      expect(res.accepted, 4);
      final req = fake.to('POST /v1/events').single;
      expect(req.headers['authorization'], 'Bearer secret-token-value');
      expect(req.json, {
        'events': [
          {'type': 'app_open', 'clientTime': '2026-11-04T09:00:00.000Z'},
          {
            'type': 'screen_view',
            'props': {'screen': 'product_page'},
            'clientTime': '2026-11-04T09:00:00.000Z',
          },
          {
            'type': 'product_view',
            'props': {'productId': 12},
            'clientTime': '2026-11-04T09:00:00.000Z',
          },
          {
            'type': 'product_favorited',
            'props': {'productId': 12, 'favorited': true},
            'clientTime': '2026-11-04T09:00:00.000Z',
          },
        ],
      });
    });

    test('free text cannot be put into an event', () {
      for (final bad in [
        'Привет мир',
        'Search: my skin',
        'A',
        '',
        'x' * 41,
        'a b',
      ]) {
        expect(
          () => AppEvent.screenView(bad),
          throwsArgumentError,
          reason: bad,
        );
      }
      expect(() => AppEvent.productView(0), throwsArgumentError);
      expect(() => AppEvent.productView(-3), throwsArgumentError);
      // the allowed list is closed: four types
      expect(AppEventType.values.map((t) => t.wire), [
        'app_open',
        'screen_view',
        'product_view',
        'product_favorited',
      ]);
    });

    test('120 events go in batches of 50 (50 + 50 + 20)', () async {
      await registered();
      fake.otherwise('POST /v1/events', const Say(201));
      final res = await api.sendEvents([
        for (var i = 0; i < 120; i++) AppEvent.appOpen(),
      ]);
      expect(res.accepted, 120);
      final sizes = [
        for (final r in fake.to('POST /v1/events'))
          (r.json as Map)['events'].length,
      ];
      expect(sizes, [50, 50, 20]);
    });

    test('a failure keeps what was delivered and is not repeated', () async {
      await registered();
      fake.queue('POST /v1/events', [
        const Say(201, {'accepted': 50}),
        const Say(503, {'message': 'down'}),
      ]);
      final res = await api.sendEvents([
        for (var i = 0; i < 120; i++) AppEvent.appOpen(),
      ]);
      expect(res.ok, isFalse);
      expect(res.accepted, 50);
      expect(res.error, isA<ServerUnavailable>());
      expect(
        fake.to('POST /v1/events').length,
        2,
        reason: 'no repeat, no third batch',
      );
    });

    test('a refused token drops the stored credentials', () async {
      await registered();
      fake.otherwise(
        'POST /v1/events',
        const Say(401, {
          'error': 'unauthorized',
          'message': 'Unknown user token',
        }),
      );
      final res = await api.sendEvents([AppEvent.appOpen()]);
      expect(res.error, isA<ServerUnauthorized>());
      expect(store.credentials, isNull);
      expect(await api.isRegistered, isFalse);
    });
  });

  group('profile and reactions (prepared payloads)', () {
    AppUser user({String source = 'questionnaire', int? birthYear = 2001}) =>
        AppUser(
          id: 1,
          firstName: 'Имя',
          lastName: 'Фамилия',
          email: 'someone@example.test',
          phone: '+7 700 000 00 00',
          city: 'Астана',
          skinType: 'Сухая',
          skinTone: 'Светлый',
          undertone: 'Тёплый',
          colorType: 'Весна',
          skinConcerns: const ['Пигментация', 'Сухость'],
          beautySource: source,
          beautyConfidence: 0.8,
          birthYear: birthYear,
          avatarPath: '/photos/face.jpg',
        );

    test('profile: only year, skin type and concerns', () {
      final p = ProfileSyncPayload.fromUser(
        user(),
        now: DateTime.utc(2026, 11, 4),
      );
      expect(p.toJson(), {
        'birthYear': 2001,
        'skinType': 'Сухая',
        'skinConcerns': ['Пигментация', 'Сухость'],
      });
      final text = jsonEncode(p.toJson());
      for (final secret in [
        'Имя',
        'Фамилия',
        'someone@',
        '+7',
        'Астана',
        'Весна',
        'Тёплый',
        'Светлый',
        'face.jpg',
        '0.8',
      ]) {
        expect(text, isNot(contains(secret)), reason: secret);
      }
    });

    test('profile: a photo analysis took part, so skin data is left out', () {
      final p = ProfileSyncPayload.fromUser(
        user(source: 'questionnaire_photo'),
        now: DateTime.utc(2026, 11, 4),
      );
      expect(p.toJson(), {
        'birthYear': 2001,
        'skinType': null,
        'skinConcerns': <String>[],
      });
    });

    test('profile: a silly year is not sent, no year clears it', () {
      final now = DateTime.utc(2026, 11, 4);
      for (final y in [1899, 2027, 3000, null]) {
        expect(
          ProfileSyncPayload.fromUser(user(birthYear: y), now: now).birthYear,
          isNull,
          reason: '$y',
        );
      }
      expect(
        ProfileSyncPayload.fromUser(user(birthYear: 2026), now: now).birthYear,
        2026,
      );
    });

    test('profile push: PUT with the token, repeated on 503', () async {
      await registered();
      fake.queue('PUT /v1/profile', [const Say(503), const Say(200, {})]);
      await api.pushProfile(
        const ProfileSyncPayload(birthYear: 1999, skinType: 'Сухая'),
      );
      final puts = fake.to('PUT /v1/profile').toList();
      expect(puts.length, 2);
      expect(puts.first.headers['authorization'], 'Bearer secret-token-value');
      expect(puts.last.json, {
        'birthYear': 1999,
        'skinType': 'Сухая',
        'skinConcerns': <String>[],
      });
    });

    test('reaction: no notes, no photo, no product name', () {
      final r = Reaction(
        id: 7,
        productId: 3,
        productName: 'Секретный крем',
        art: 'tube',
        color: 1,
        title: '  Покраснение ',
        severity: 3,
        date: DateTime(2026, 5, 9, 23, 30),
        notes: 'у меня аллергия на всё, живу на ул. Такой-то',
        photoPath: '/photos/skin.jpg',
      );
      final p = ReactionSyncPayload.tryFrom(r)!;
      expect(p.clientId, '7');
      expect(p.toJson(), {
        'productId': 3,
        'title': 'Покраснение',
        'severity': 3,
        'date': '2026-05-09',
      });
      final text = jsonEncode(p.toJson());
      for (final secret in ['аллергия', 'ул.', 'skin.jpg', 'Секретный']) {
        expect(text, isNot(contains(secret)));
      }
    });

    test('reaction: entries that cannot be sent as they are are skipped', () {
      Reaction make({
        String title = 't',
        int severity = 2,
        int productId = 1,
      }) => Reaction(
        id: 1,
        productId: productId,
        productName: 'p',
        art: 'a',
        color: 0,
        title: title,
        severity: severity,
        date: DateTime(2026, 1, 1),
        notes: '',
      );
      expect(ReactionSyncPayload.tryFrom(make(title: '   ')), isNull);
      expect(ReactionSyncPayload.tryFrom(make(severity: 0)), isNull);
      expect(ReactionSyncPayload.tryFrom(make(severity: 6)), isNull);
      expect(ReactionSyncPayload.tryFrom(make(productId: 0)), isNull);
      expect(ReactionSyncPayload.tryFrom(make()), isNotNull);
    });

    test('reaction push and delete go to the entry of that local id', () async {
      await registered();
      await api.pushReaction(
        const ReactionSyncPayload(
          clientId: '7',
          productId: 3,
          title: 't',
          severity: 2,
          date: '2026-05-09',
        ),
      );
      await api.deleteReaction(7);
      expect(fake.to('PUT /v1/reactions/7').length, 1);
      expect(fake.to('DELETE /v1/reactions/7').length, 1);
      expect(
        fake.to('PUT /v1/reactions/7').single.headers['authorization'],
        'Bearer secret-token-value',
      );
    });

    test(
      'the server refusing an entry (400) is ServerRejected, not repeated',
      () async {
        await registered();
        fake.otherwise(
          'PUT /v1/reactions/7',
          const Say(400, {
            'error': 'bad_request',
            'message': 'Unknown "productId"',
          }),
        );
        await expectLater(
          api.pushReaction(
            const ReactionSyncPayload(
              clientId: '7',
              productId: 999,
              title: 't',
              severity: 2,
              date: '2026-05-09',
            ),
          ),
          throwsA(isA<ServerRejected>()),
        );
        expect(fake.to('PUT /v1/reactions/7').length, 1);
      },
    );
  });

  group('withdrawing consent and deleting server data', () {
    test('consent is erased first, then the server data is deleted', () async {
      await registered();
      fake.otherwise('DELETE /v1/profile', const Say(204));
      final deleted = await api.withdrawConsent();
      expect(deleted, isTrue);
      expect((await api.consent()).scopes, isEmpty);
      expect(store.credentials, isNull);
      final del = fake.to('DELETE /v1/profile').single;
      expect(del.headers['authorization'], 'Bearer secret-token-value');
    });

    test(
      'offline: consent is still erased, the deletion can be repeated',
      () async {
        await registered();
        final url = fake.url;
        await fake.close();
        final offline = build(baseUrl: url);
        expect(await offline.withdrawConsent(), isFalse);
        expect((await offline.consent()).scopes, isEmpty);
        expect(
          store.credentials,
          isNotNull,
          reason: 'kept so that deleting can be retried',
        );
        // nothing can be sent now
        await expectLater(
          offline.sendEvents([AppEvent.appOpen()]),
          throwsA(isA<ConsentRequired>()),
        );
        // the server is back
        fake = await FakeServer.start();
        fake.otherwise('DELETE /v1/profile', const Say(204));
        final back = build();
        await back.deleteServerData();
        expect(store.credentials, isNull);
      },
    );

    test('keeping the server data when the user only stops sharing', () async {
      await registered();
      expect(await api.withdrawConsent(deleteServerData: false), isTrue);
      expect(fake.to('DELETE /v1/profile'), isEmpty);
      expect(store.credentials, isNotNull);
    });

    test('a token the server no longer knows is simply forgotten', () async {
      await registered();
      fake.otherwise(
        'DELETE /v1/profile',
        const Say(401, {'message': 'Unknown user token'}),
      );
      await api.deleteServerData();
      expect(store.credentials, isNull);
    });

    test('nothing registered: no request', () async {
      await api.deleteServerData();
      expect(fake.seen, isEmpty);
    });
  });

  group('the layer stays separate from the app (this step)', () {
    final lib = Directory('lib');
    final dartFiles = lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    test(
      'only the public price sync uses it, and only the plain HTTP client',
      () {
        // The profile / event layer (CosmetixServer, consent, device state) is
        // still not wired: that needs the approved data rules first. The price
        // sync reads a PUBLIC snapshot with a plain GET and sends nothing about
        // the user, so it may use ServerHttp and the exceptions, nothing else.
        final allowed = {
          'lib/app.dart',
          'lib/services/offer_sync_service.dart',
        };
        final users = [
          for (final f in dartFiles)
            if (!f.path.contains('lib/services/server/') &&
                f.readAsStringSync().contains('services/server/'))
              f.path,
        ];
        expect(users.toSet().difference(allowed), isEmpty);
        for (final f in users) {
          final text = File(f).readAsStringSync();
          for (final banned in const [
            'cosmetix_server.dart',
            'server_consent.dart',
            'server_state',
          ]) {
            expect(text.contains(banned), isFalse, reason: '$f uses $banned');
          }
        }
        final sync = File(
          'lib/services/offer_sync_service.dart',
        ).readAsStringSync();
        expect(sync.contains("'POST'"), isFalse);
        expect(sync.contains('json:'), isFalse, reason: 'nothing is sent');
      },
    );

    test('no hardware or advertising identifiers anywhere in it', () {
      final banned = RegExp(
        r'device_info|identifierForVendor|advertisingId|advertising_id|androidId|android_id|imei|macAddress|serialNumber|Platform\.operatingSystemVersion|Platform\.localHostname',
        caseSensitive: false,
      );
      for (final f in dartFiles.where(
        (f) => f.path.contains('lib/services/server/'),
      )) {
        expect(banned.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
      }
    });

    test('it never touches the photo or the analysis code', () {
      final banned = RegExp(
        r'vision_analyzer|beauty_profile_merger|avatar_service|image_picker|app_paths|photoPath|avatarPath',
      );
      for (final f in dartFiles.where(
        (f) => f.path.contains('lib/services/server/'),
      )) {
        // comments may say "never the photo": only imports and fields count
        final code = f
            .readAsLinesSync()
            .where(
              (l) =>
                  !l.trimLeft().startsWith('///') &&
                  !l.trimLeft().startsWith('//'),
            )
            .join('\n');
        expect(banned.hasMatch(code), isFalse, reason: f.path);
      }
    });

    test('no timers, no start-up hooks: nothing runs by itself', () {
      final banned = RegExp(
        r'Timer\.|Timer\(|WidgetsBindingObserver|runApp|main\(\)|Isolate\.|compute\(',
      );
      for (final f in dartFiles.where(
        (f) => f.path.contains('lib/services/server/'),
      )) {
        expect(banned.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
      }
    });
  });
}
