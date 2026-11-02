import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/core/beauty/beauty_codes.dart';
import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/models/ai_models.dart';
import 'package:cosmetix/models/beauty_profile.dart';
import 'package:cosmetix/providers/ai_provider.dart';
import 'package:cosmetix/providers/chat_provider.dart';
import 'package:cosmetix/repositories/chat_repository.dart';
import 'package:cosmetix/repositories/product_repository.dart';
import 'package:cosmetix/repositories/safety_repository.dart';
import 'package:cosmetix/repositories/settings_repository.dart';
import 'package:cosmetix/repositories/user_repository.dart';
import 'package:cosmetix/services/ai/ai_client.dart';
import 'package:cosmetix/services/ai/ai_config.dart';
import 'package:cosmetix/services/ai/beauty_profile_merger.dart';
import 'package:cosmetix/services/ai/product_classifier.dart';
import 'package:cosmetix/services/ai/recommendation_refiner.dart';
import 'package:cosmetix/services/ai/vision_analyzer.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/services/assistant_service.dart';
import 'package:cosmetix/services/recommendation_service.dart';

/// A tiny fake Cosmetix AI proxy on the loopback interface.
class FakeAiProxy {
  FakeAiProxy._(this._server);

  final HttpServer _server;
  final requests = <Map<String, Object?>>[];
  final headers = <HttpHeaders>[];

  /// `text` of /v1/chat. Null -> the error below is returned instead.
  String? chatAnswer = '{}';
  bool mock = false;
  String mode = 'claude';
  Duration delay = Duration.zero;
  int chatCalls = 0;

  /// Error answer used when [chatAnswer] is null.
  int errorStatus = 500;
  Map<String, Object?> errorBody = {'error': 'internal', 'message': 'boom'};
  String? retryAfter;

  String get url => 'http://127.0.0.1:${_server.port}';

  static Future<FakeAiProxy> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeAiProxy._(server);
    unawaited(
      server.forEach((req) async {
        final body = await utf8.decoder.bind(req).join();
        await Future<void>.delayed(fake.delay);
        final res = req.response;
        res.headers.contentType = ContentType.json;
        if (req.uri.path == '/health') {
          res.write(
            jsonEncode({
              'ok': true,
              'mode': fake.mode,
              'model': fake.mode == 'mock' ? null : 'claude-haiku-5-5',
            }),
          );
        } else if (req.uri.path == '/v1/chat') {
          fake.chatCalls++;
          fake.headers.add(req.headers);
          fake.requests.add(jsonDecode(body) as Map<String, Object?>);
          if (fake.chatAnswer == null) {
            res.statusCode = fake.errorStatus;
            if (fake.retryAfter != null) {
              res.headers.set('retry-after', fake.retryAfter!);
            }
            res.write(jsonEncode(fake.errorBody));
          } else {
            res.write(
              jsonEncode({
                'text': fake.chatAnswer,
                'mock': fake.mock,
                'usage': {'inputTokens': 1, 'outputTokens': 1},
              }),
            );
          }
        } else {
          res.statusCode = 404;
        }
        await res.close();
      }),
    );
    return fake;
  }

  Future<void> stop() => _server.close(force: true);
}

const _validVision =
    '{"skinTone":"light","undertone":"cool","colorType":"summer",'
    '"observations":["even skin"],"confidence":0.82,"explanation":"ok"}';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late FakeAiProxy fake;
  late AiConfig config;
  late AiClient client;

  setUp(() async {
    fake = await FakeAiProxy.start();
    config = AiConfig(baseUrl: fake.url);
    client = AiClient(() => config);
  });
  tearDown(() => fake.stop());

  group('connection and offline fallback', () {
    test('health tells the real Claude from test mode', () async {
      final real = await client.health();
      expect(real.isMock, isFalse);
      expect(real.model, 'claude-haiku-5-5');
      fake.mode = 'mock';
      final test = await client.health();
      expect(test.isMock, isTrue);
      expect(test.model, isNull);
    });

    test('something that is not the proxy is AiBadResponse', () async {
      final other = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => other.close(force: true));
      unawaited(
        other.forEach((r) {
          r.response
            ..write('<html>hi</html>')
            ..close();
        }),
      );
      final c = AiClient(
        () => AiConfig(baseUrl: 'http://127.0.0.1:${other.port}'),
      );
      expect(c.health(), throwsA(isA<AiBadResponse>()));
    });

    test('an unreachable server is AiUnavailable, not a crash', () async {
      final offline = AiClient(
        () => const AiConfig(baseUrl: 'http://127.0.0.1:1'),
      );
      expect(offline.health(), throwsA(isA<AiUnavailable>()));
    });

    test('no server address configured', () {
      final none = AiClient(() => const AiConfig(baseUrl: ''));
      expect(
        none.chat(messages: const [AiMessage('user', 'hi')]),
        throwsA(isA<AiUnavailable>()),
      );
    });

    test('a slow server times out', () async {
      fake.delay = const Duration(milliseconds: 600);
      expect(
        client.chat(
          messages: const [AiMessage('user', 'hi')],
          timeout: const Duration(milliseconds: 150),
        ),
        throwsA(isA<AiTimeout>()),
      );
    });

    test('proxy errors map to typed exceptions', () async {
      fake.chatAnswer = null;
      Future<Object?> failWith(int status, [String? retryAfter]) async {
        fake.errorStatus = status;
        fake.errorBody = {'error': 'e$status', 'message': 'm$status'};
        fake.retryAfter = retryAfter;
        try {
          await client.chat(messages: const [AiMessage('user', 'hi')]);
        } catch (e) {
          return e;
        }
        return null;
      }

      final limited = await failWith(429, '12');
      expect(limited, isA<AiRateLimited>());
      expect((limited! as AiRateLimited).retryAfter, 12);
      expect(await failWith(504), isA<AiTimeout>());
      expect(await failWith(503), isA<AiUnavailable>());
      final auth = await failWith(401);
      expect(auth, isA<AiServerError>());
      expect((auth! as AiServerError).statusCode, 401);
      expect(await failWith(500), isA<AiServerError>());
    });

    test('an empty answer is AiBadResponse', () async {
      fake.chatAnswer = '  ';
      expect(
        client.chat(messages: const [AiMessage('user', 'hi')]),
        throwsA(isA<AiBadResponse>()),
      );
    });

    test('test-mode answers are flagged', () async {
      fake.mock = true;
      fake.chatAnswer = '[ТЕСТОВЫЙ РЕЖИМ] hi';
      final r = await client.chat(messages: const [AiMessage('user', 'hi')]);
      expect(r.mock, isTrue);
    });

    test('request shape: system split out, json flag, token header', () async {
      config = AiConfig(baseUrl: fake.url, appToken: 'tok');
      fake.chatAnswer = 'ok';
      await client.chat(
        json: true,
        temperature: 0.2,
        maxTokens: 123,
        messages: const [
          AiMessage('system', 'be nice'),
          AiMessage('user', 'hello'),
        ],
      );
      final sent = fake.requests.single;
      expect(sent['system'], 'be nice');
      expect(sent['json'], isTrue);
      expect(sent['maxTokens'], 123);
      expect((sent['messages']! as List).single, {
        'role': 'user',
        'content': 'hello',
      });
      expect(fake.headers.single.value('x-app-token'), 'tok');
      // no model and no key ever leave the app
      expect(sent.containsKey('model'), isFalse);
      expect(jsonEncode(sent), isNot(contains('sk-')));
    });

    test('a very long message is cut before sending (cost control)', () async {
      fake.chatAnswer = 'ok';
      await client.chat(messages: [AiMessage('user', 'x' * 20000)]);
      final content =
          ((fake.requests.single['messages']! as List).single
                  as Map)['content']!
              as String;
      expect(content.length, AiClient.maxMessageChars);
    });

    test('AiProvider reports offline/online and never throws', () async {
      final h = DatabaseHelper(path: inMemoryDatabasePath);
      addTearDown(h.close);
      final ai = AiProvider(
        SettingsRepository(h),
        initial: const AiConfig(baseUrl: 'http://127.0.0.1:1'),
      );
      await ai.testConnection();
      expect(ai.status, AiStatus.offline);
      await ai.update(baseUrl: fake.url);
      await ai.testConnection();
      expect(ai.status, AiStatus.online);
      expect(ai.isMock, isFalse);
      expect(ai.model, 'claude-haiku-5-5');
      fake.mode = 'mock';
      await ai.testConnection();
      expect(ai.isMock, isTrue);
      // the address is stored in SQLite and survives a reload
      final again = AiProvider(
        SettingsRepository(h),
        initial: const AiConfig(baseUrl: ''),
      );
      await again.load();
      expect(again.config.baseUrl, fake.url);
    });

    test('an old Ollama address is dropped on load', () async {
      final h = DatabaseHelper(path: inMemoryDatabasePath);
      addTearDown(h.close);
      await SettingsRepository(h).set('ai_base_url', 'http://10.0.0.5:11434');
      final ai = AiProvider(
        SettingsRepository(h),
        initial: const AiConfig(baseUrl: ''),
      );
      await ai.load();
      expect(ai.config.baseUrl, '');
    });

    test('base url normalization', () {
      expect(
        const AiConfig(baseUrl: '192.168.1.50').baseUri.toString(),
        'http://192.168.1.50:8787',
      );
      expect(
        const AiConfig(baseUrl: '192.168.1.50:9000').baseUri.toString(),
        'http://192.168.1.50:9000',
      );
      expect(
        const AiConfig(baseUrl: 'https://ai.example.com/').baseUri.toString(),
        'https://ai.example.com',
      );
      expect(const AiConfig(baseUrl: ' ').baseUri, isNull);
    });
  });

  group('consent', () {
    test('nothing is shared until the user agrees, and it persists', () async {
      final h = DatabaseHelper(path: inMemoryDatabasePath);
      addTearDown(h.close);
      final ai = AiProvider(SettingsRepository(h));
      await ai.load();
      expect(ai.shareProfile, isFalse);
      expect(ai.sharePhotos, isFalse);
      expect(ai.profileAsked, isFalse);
      await ai.setShareProfile(true);
      await ai.setSharePhotos(true);
      final again = AiProvider(SettingsRepository(h));
      await again.load();
      expect(again.shareProfile, isTrue);
      expect(again.sharePhotos, isTrue);
      expect(again.profileAsked, isTrue);
      again.resetToDefaults();
      expect(again.shareProfile, isFalse);
    });
  });

  group('vision analysis JSON', () {
    test('valid answer', () {
      final a = VisionAnalysis.parse(_validVision);
      expect(a.skinTone, SkinTone.light);
      expect(a.undertone, Undertone.cool);
      expect(a.colorType, ColorType.summer);
      expect(a.confidence, 0.82);
    });

    test('JSON wrapped in a code fence and prose', () {
      final a = VisionAnalysis.parse('Sure!\n```json\n$_validVision\n```');
      expect(a.colorType, ColorType.summer);
    });

    test('unsupported values become null, confidence is clamped', () {
      final a = VisionAnalysis.parse(
        '{"skinTone":"purple","undertone":"warm","colorType":"monsoon","confidence":7}',
      );
      expect(a.skinTone, isNull);
      expect(a.colorType, isNull);
      expect(a.undertone, Undertone.warm);
      expect(a.confidence, 1.0);
    });

    test('invalid or empty answers throw AiBadResponse', () {
      for (final bad in [
        'not json at all',
        '{"skinTone": ',
        '{}',
        '{"skinTone":"?","undertone":"?","colorType":"?"}',
        '[1,2,3]',
      ]) {
        expect(
          () => VisionAnalysis.parse(bad),
          throwsA(isA<AiBadResponse>()),
          reason: bad,
        );
      }
    });

    test('analyzer sends the photo and parses the answer', () async {
      fake.chatAnswer = _validVision;
      final v = VisionAnalyzer(client);
      final a = await v.analyze(Uint8List.fromList([1, 2, 3, 4]));
      expect(a.undertone, Undertone.cool);
      final sent = fake.requests.single;
      expect(sent['json'], isTrue);
      final msg = (sent['messages']! as List).single as Map;
      expect((msg['images'] as List).single, base64Encode([1, 2, 3, 4]));
    });

    test('an invalid model answer does not crash the analyzer', () async {
      fake.chatAnswer = 'I cannot help with that';
      final v = VisionAnalyzer(client);
      expect(v.analyze(Uint8List.fromList([1])), throwsA(isA<AiBadResponse>()));
    });

    test('huge or empty photos are rejected before any request', () async {
      final v = VisionAnalyzer(client);
      expect(v.analyze(Uint8List(0)), throwsA(isA<AiBadResponse>()));
      expect(
        v.analyze(Uint8List(VisionAnalyzer.maxBytes + 1)),
        throwsA(isA<AiBadResponse>()),
      );
      expect(fake.chatCalls, 0);
    });

    test('the temporary photo file is deleted after analysis', () async {
      fake.chatAnswer = _validVision;
      final f = File('${Directory.systemTemp.path}/cosmetix_test_photo.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      await VisionAnalyzer(client).analyzeFile(f);
      expect(f.existsSync(), isFalse);
    });
  });

  group('questionnaire + photo = final profile', () {
    const q = BeautyProfile(
      skinType: SkinType.dry,
      skinTone: SkinTone.light,
      undertone: Undertone.warm,
      colorType: ColorType.spring,
      concerns: {SkinConcern.dryness},
    );
    VisionAnalysis v({double c = 0.9, Undertone? u, ColorType? t}) =>
        VisionAnalysis(
          skinTone: SkinTone.medium,
          undertone: u ?? Undertone.cool,
          colorType: t ?? ColorType.summer,
          confidence: c,
        );

    test('without a photo (skipped) the questionnaire is the profile', () {
      final m = BeautyProfileMerger.merge(q, null);
      expect(m.profile.colorType, ColorType.spring);
      expect(m.profile.source, BeautySource.questionnaire);
      expect(m.photoUsed, isFalse);
    });

    test('questionnaire beats a disagreeing photo', () {
      final m = BeautyProfileMerger.merge(q, v());
      expect(m.profile.undertone, Undertone.warm);
      expect(m.profile.colorType, ColorType.spring);
      expect(m.profile.skinType, SkinType.dry);
      expect(m.profile.source, BeautySource.questionnairePhoto);
    });

    test('a confident photo only fills a neutral undertone', () {
      const neutral = BeautyProfile(
        skinType: SkinType.dry,
        undertone: Undertone.neutral,
        colorType: ColorType.summer,
      );
      expect(
        BeautyProfileMerger.merge(neutral, v()).profile.undertone,
        Undertone.cool,
      );
      expect(
        BeautyProfileMerger.merge(neutral, v(c: 0.3)).profile.undertone,
        Undertone.neutral,
      );
    });

    test('a low-confidence photo is not used at all', () {
      final m = BeautyProfileMerger.merge(q, v(c: 0.2));
      expect(m.photoUsed, isFalse);
      expect(m.profile.source, BeautySource.questionnaire);
    });
  });

  group('AI ranking can only reorder', () {
    test('applyOrder is a permutation: unknown ids dropped, missing kept', () {
      expect(RecommendationRefiner.applyOrder([1, 2, 3], [3, 99, 1, 1]), [
        3,
        1,
        2,
      ]);
      expect(RecommendationRefiner.applyOrder([1, 2], []), [1, 2]);
    });

    test('invalid answers throw', () {
      expect(
        () => RecommendationRefiner.parseOrder('nope'),
        throwsA(isA<AiBadResponse>()),
      );
      expect(
        () => RecommendationRefiner.parseOrder('{"x":1}'),
        throwsA(isA<AiBadResponse>()),
      );
      expect(RecommendationRefiner.parseOrder('{"order":[3,"a",1.0]}'), [3, 1]);
    });
  });

  group('product classification cache', () {
    late DatabaseHelper h;
    late ProductRepository products;
    late ProductClassifier classifier;

    setUp(() {
      h = DatabaseHelper(path: inMemoryDatabasePath);
      products = ProductRepository(h);
      classifier = ProductClassifier(client, products, SafetyRepository(h));
    });
    tearDown(() => h.close());

    test('classifies once, caches in SQLite, never asks twice', () async {
      fake.chatAnswer =
          '{"colorTypes":["summer"],"undertones":["cool"],"skinTypes":["dry"],'
          '"concerns":["dryness"],"confidence":0.9,"explanation":"x"}';
      final first = await classifier.classifyPending(1, limit: 3);
      expect(first.classified, 3);
      expect(await products.classifiedCount(), 3);
      final calls = fake.chatCalls;
      await classifier.classifyPending(1, limit: 3);
      // the first 3 are cached; only 3 new products are asked about
      expect(fake.chatCalls, calls + 3);
      final c = await products.candidates(1);
      final id = (await products.unclassified(1)).length; // products left
      expect(id, greaterThan(0));
      // AI traits are merged into the candidates
      expect(
        c.where((x) => x.skinTypes.contains(SkinType.dry)).length,
        greaterThanOrEqualTo(3),
      );
    });

    test('skincare gets no color traits from the AI', () async {
      fake.chatAnswer =
          '{"colorTypes":["summer"],"undertones":["cool"],"skinTypes":["oily"],"confidence":0.9}';
      final serum = (await products.getAll(
        1,
      )).firstWhere((p) => p.category == 'Уход за лицом');
      final c = await classifier.classify(serum);
      expect(c.colorTypes, isEmpty);
      expect(c.undertones, isEmpty);
      expect(c.skinTypes, {SkinType.oily});
    });

    test('low confidence is cached but adds no traits', () async {
      fake.chatAnswer =
          '{"skinTypes":["oily"],"confidence":0.2,"explanation":"unsure"}';
      final p = (await products.getAll(1)).first;
      await products.saveAiClassification(
        p.id,
        'm',
        await classifier.classify(p),
      );
      final cand = (await products.candidates(
        1,
      )).firstWhere((x) => x.product.id == p.id);
      expect(cand.skinTypes.contains(SkinType.oily), isFalse);
      expect(await products.classifiedCount(), 1);
    });

    test('invalid JSON for a product is counted, others continue', () async {
      fake.chatAnswer = 'garbage';
      final r = await classifier.classifyPending(1, limit: 2);
      expect(r.classified, 0);
      expect(r.failed, 2);
      expect(r.stoppedOffline, isFalse);
      expect(await products.classifiedCount(), 0);
    });

    test('offline stops the batch gracefully', () async {
      await fake.stop();
      final r = await classifier.classifyPending(1, limit: 2);
      expect(r.stoppedOffline, isTrue);
      expect(r.classified, 0);
      fake = await FakeAiProxy.start(); // for tearDown
    });
  });

  group('chat assistant', () {
    late DatabaseHelper h;
    late AssistantService bot;

    setUp(() {
      h = DatabaseHelper(path: inMemoryDatabasePath);
      final products = ProductRepository(h);
      final safety = SafetyRepository(h);
      bot = AssistantService(
        RecommendationService(products, safety, UserRepository(h)),
        client,
      );
    });
    tearDown(() => h.close());

    test(
      'with consent the model receives the Beauty Profile, blacklist and product',
      () async {
        fake.chatAnswer = 'It suits you.';
        final out = await bot.reply(
          userId: 1,
          text: 'Подходит ли мне Сыворотка Niacinamide?',
          history: const [],
          shareProfile: true,
        );
        expect(out, 'It suits you.');
        final system = fake.requests.single['system']! as String;
        expect(system, contains('color type: Весна')); // demo profile
        expect(system, contains('skin concerns: Сухость и шелушение'));
        expect(system, contains('Парабены')); // enabled blacklist
        expect(system, contains('Niacinamide')); // the product in question
        expect(system, contains('ingredients:'));
        expect(system, contains('Never invent'));
        expect(system, contains('NOT a doctor'));
        expect(system, contains('no data'));
        expect(system, contains('never promise'));
        expect(
          fake.requests.single['maxTokens'],
          AssistantService.maxAnswerTokens,
        );
      },
    );

    test(
      'without consent the profile and blacklist never leave the app',
      () async {
        final db = await h.database;
        // make a blacklisted product exist: enable parabens for the demo user
        await db.update('blacklist', {
          'enabled': 1,
        }, where: "group_key = 'parabens'");
        fake.chatAnswer = 'ok';
        await bot.reply(
          userId: 1,
          text: 'Подходит ли мне Сыворотка Niacinamide?',
          history: const [],
        );
        final system = fake.requests.single['system']! as String;
        expect(system, contains('not shared by the user'));
        expect(system, isNot(contains('Весна')));
        expect(system, isNot(contains('Сухость и шелушение')));
        expect(system, isNot(contains('Парабены')));
        expect(system, isNot(contains('match:')));
        // the whole request must not contain the user's email or phone either
        final all = jsonEncode(fake.requests.single);
        expect(all, isNot(contains('ainara')));
        expect(all, isNot(contains('+7 707')));
      },
    );

    test(
      'blacklisted products are hidden from the model without consent',
      () async {
        final ctx = await RecommendationService(
          ProductRepository(h),
          SafetyRepository(h),
          UserRepository(h),
        ).loadContext(1);
        final hidden = ctx.candidates.where(
          (c) => RecommendationService.isBlacklisted(c, ctx.blacklist),
        );
        final system = AssistantService.buildSystemPrompt(
          ctx: ctx,
          question: 'привет',
          language: 'Russian',
          shareProfile: false,
        );
        for (final c in hidden) {
          expect(system, isNot(contains(c.product.name)));
        }
      },
    );

    test('the catalog is capped to save tokens', () async {
      final ctx = await RecommendationService(
        ProductRepository(h),
        SafetyRepository(h),
        UserRepository(h),
      ).loadContext(1);
      final system = AssistantService.buildSystemPrompt(
        ctx: ctx,
        question: 'привет',
        language: 'Russian',
      );
      final lines = system
          .split('\n')
          .where((l) => l.startsWith('- ') && l.contains('('));
      expect(
        lines.length,
        lessThanOrEqualTo(AssistantService.maxCatalogLines + 6),
      );
    });

    test(
      'rate limit surfaces as a friendly state with the wait time',
      () async {
        fake.chatAnswer = null;
        fake.errorStatus = 429;
        fake.errorBody = {'error': 'rate_limited', 'message': 'slow down'};
        fake.retryAfter = '30';
        final chat = ChatProvider(ChatRepository(h), bot);
        await chat.load(1);
        await chat.send('Привет');
        expect(chat.aiUnavailable, isTrue);
        expect(chat.aiFailure, AiFailure.rateLimited);
        expect(chat.retryAfter, 30);
      },
    );

    test('an unset address is reported as not configured', () async {
      config = const AiConfig(baseUrl: '');
      final chat = ChatProvider(ChatRepository(h), bot);
      await chat.load(1);
      await chat.send('Привет');
      expect(chat.aiFailure, AiFailure.notConfigured);
    });

    test('a serious reaction always gets the safety advice', () async {
      fake.chatAnswer = 'Try a cream.';
      final out = await bot.reply(
        userId: 1,
        text: 'после крема сильный отёк лица',
        history: const [],
      );
      expect(out, contains('обратитесь к врачу'));
      expect(AssistantService.isSeriousReaction('I have swelling'), isTrue);
      expect(AssistantService.isSeriousReaction('which lipstick?'), isFalse);
    });

    test(
      'offline: ChatProvider keeps the conversation and offers retry',
      () async {
        final chat = ChatProvider(ChatRepository(h), bot);
        await chat.load(1);
        final before = chat.messages.length;
        await fake.stop();
        await chat.send('Привет');
        expect(chat.aiUnavailable, isTrue);
        expect(chat.typing, isFalse);
        expect(chat.messages.length, before + 1); // only the user message
        fake = await FakeAiProxy.start();
        config = config.copyWith(baseUrl: fake.url);
        fake.chatAnswer = 'Hello!';
        await chat.retry();
        expect(chat.aiUnavailable, isFalse);
        expect(chat.messages.last.text, 'Hello!');
        expect(chat.messages.length, before + 2);
      },
    );

    test('history is sent but limited', () async {
      fake.chatAnswer = 'ok';
      final chat = ChatProvider(ChatRepository(h), bot);
      await chat.load(1);
      for (var i = 0; i < 6; i++) {
        await chat.send('вопрос $i');
      }
      final msgs = (fake.requests.last['messages']! as List);
      // at most 8 history messages + the question (system is a separate field)
      expect(msgs.length, lessThanOrEqualTo(AssistantService.historyLimit + 1));
      expect((msgs.last as Map)['content'], 'вопрос 5');
    });
  });

  test('plainText removes markdown emphasis but keeps the words', () {
    expect(
      AssistantService.plainText(
        'Вот:\n\n1. **Flower Knows Тинт** (3 200 тг) — бархат.\n'
        '* первый пункт\n- второй\n## Итог\n*Важно: стоп*',
      ),
      'Вот:\n\n1. Flower Knows Тинт (3 200 тг) — бархат.\n'
      '• первый пункт\n• второй\nИтог\nВажно: стоп',
    );
    expect(
      AssistantService.plainText('2 * 3 = 6, цена 5*'),
      '2 * 3 = 6, цена 5*',
    );
  });

  group('product cards in answers', () {
    Product prod(int id, String brand, String name) => Product(
      id: id,
      brand: brand,
      name: name,
      category: 'Макияж',
      zone: 'Губы',
      price: 3200,
      inStock: true,
      art: 'tube',
      color: 0xFFE06A7C,
      description: '',
      naturalPercent: 80,
      createdAt: 0,
    );
    final tint = prod(12, 'Flower Knows', 'Strawberry Lip Tint');
    final ink = prod(7, 'Peripera', 'Тинт Ink');

    test('parseReply strips markers and keeps the ids in order', () {
      final r = AssistantService.parseReply(
        'Возьмите Strawberry Lip Tint [#12] или Тинт Ink [#7] [#12].',
      );
      expect(r.text, 'Возьмите Strawberry Lip Tint или Тинт Ink.');
      expect(r.productIds, [12, 7]);
      expect(AssistantService.parseReply('Без товаров').productIds, isEmpty);
    });

    test('at most three cards per answer', () {
      final r = AssistantService.parseReply('[#1] [#2] [#3] [#4] [#5]');
      expect(r.productIds, [1, 2, 3]);
    });

    test('markers for products the model may not mention are dropped', () {
      final out = AssistantService.withProductMarkers(
        'Хорош Strawberry Lip Tint [#12] и выдуманный [#99].',
        [tint, ink],
      );
      expect(AssistantService.parseReply(out).productIds, [12]);
      expect(out.contains('[#99]'), isFalse);
    });

    test('no markers: products named in the text get a marker', () {
      final out = AssistantService.withProductMarkers(
        'Подойдёт Strawberry Lip Tint за 3 200 тг.',
        [tint, ink],
      );
      expect(AssistantService.parseReply(out).productIds, [12]);
      // nothing named, nothing added
      expect(
        AssistantService.withProductMarkers('Привет!', [tint, ink]),
        'Привет!',
      );
    });

    test('a very short product name is not matched by accident', () {
      final short = prod(3, 'X', 'Крем');
      expect(
        AssistantService.withProductMarkers('Нужен крем на ночь', [short]),
        'Нужен крем на ночь',
      );
    });
  });
}
