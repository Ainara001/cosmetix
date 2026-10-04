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
import 'package:cosmetix/services/ai/ai_config.dart';
import 'package:cosmetix/services/ai/beauty_profile_merger.dart';
import 'package:cosmetix/services/ai/ollama_client.dart';
import 'package:cosmetix/services/ai/product_classifier.dart';
import 'package:cosmetix/services/ai/recommendation_refiner.dart';
import 'package:cosmetix/services/ai/vision_analyzer.dart';
import 'package:cosmetix/services/assistant_service.dart';
import 'package:cosmetix/services/recommendation_service.dart';

/// A tiny fake Ollama on the loopback interface.
class FakeOllama {
  FakeOllama._(this._server);

  final HttpServer _server;
  final requests = <Map<String, Object?>>[];

  /// Answer of /api/chat (message.content). Null -> HTTP 500.
  String? chatAnswer = '{}';
  Duration delay = Duration.zero;
  int chatCalls = 0;

  String get url => 'http://127.0.0.1:${_server.port}';

  static Future<FakeOllama> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeOllama._(server);
    unawaited(
      server.forEach((req) async {
        final body = await utf8.decoder.bind(req).join();
        await Future<void>.delayed(fake.delay);
        final res = req.response;
        if (req.uri.path == '/api/tags') {
          res.write(
            jsonEncode({
              'models': [
                {'name': 'llama3.2:latest'},
                {'name': 'llava:latest'},
              ],
            }),
          );
        } else if (req.uri.path == '/api/chat') {
          fake.chatCalls++;
          fake.requests.add(jsonDecode(body) as Map<String, Object?>);
          if (fake.chatAnswer == null) {
            res.statusCode = 500;
            res.write(jsonEncode({'error': 'model not found'}));
          } else {
            res.write(
              jsonEncode({
                'message': {'role': 'assistant', 'content': fake.chatAnswer},
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

  late FakeOllama fake;
  late AiConfig config;
  late OllamaClient client;

  setUp(() async {
    fake = await FakeOllama.start();
    config = AiConfig(
      baseUrl: fake.url,
      textModel: 'llama3.2',
      visionModel: 'llava',
    );
    client = OllamaClient(() => config);
  });
  tearDown(() => fake.stop());

  group('connection and offline fallback', () {
    test('health lists installed models', () async {
      final h = await client.health();
      expect(h.hasModel('llama3.2'), isTrue);
      expect(h.hasModel('llava'), isTrue);
      expect(h.hasModel('other'), isFalse);
    });

    test('an unreachable server is AiUnavailable, not a crash', () async {
      final offline = OllamaClient(
        () => const AiConfig(
          baseUrl: 'http://127.0.0.1:1',
          textModel: 't',
          visionModel: 'v',
        ),
      );
      expect(offline.health(), throwsA(isA<AiUnavailable>()));
    });

    test('no server address configured', () {
      final none = OllamaClient(
        () => const AiConfig(baseUrl: '', textModel: 't', visionModel: 'v'),
      );
      expect(
        none.chat(model: 't', messages: const []),
        throwsA(isA<AiUnavailable>()),
      );
    });

    test('a slow server times out', () async {
      fake.delay = const Duration(milliseconds: 600);
      expect(
        client.chat(
          model: 't',
          messages: const [OllamaMessage('user', 'hi')],
          timeout: const Duration(milliseconds: 150),
        ),
        throwsA(isA<AiTimeout>()),
      );
    });

    test('a server error (model missing) is AiServerError', () async {
      fake.chatAnswer = null;
      expect(
        client.chat(model: 'x', messages: const [OllamaMessage('user', 'hi')]),
        throwsA(isA<AiServerError>()),
      );
    });

    test('AiProvider reports offline/online and never throws', () async {
      final h = DatabaseHelper(path: inMemoryDatabasePath);
      addTearDown(h.close);
      final ai = AiProvider(
        SettingsRepository(h),
        initial: const AiConfig(
          baseUrl: 'http://127.0.0.1:1',
          textModel: 'llama3.2',
          visionModel: 'llava',
        ),
      );
      await ai.testConnection();
      expect(ai.status, AiStatus.offline);
      await ai.update(baseUrl: fake.url);
      await ai.testConnection();
      expect(ai.status, AiStatus.online);
      expect(ai.installedModels, isNotEmpty);
      // the address is stored in SQLite and survives a reload
      final again = AiProvider(
        SettingsRepository(h),
        initial: const AiConfig(baseUrl: '', textModel: 't', visionModel: 'v'),
      );
      await again.load();
      expect(again.config.baseUrl, fake.url);
    });

    test('base url normalization', () {
      expect(
        const AiConfig(
          baseUrl: '192.168.1.50:11434',
          textModel: '',
          visionModel: '',
        ).baseUri.toString(),
        'http://192.168.1.50:11434',
      );
      expect(
        const AiConfig(baseUrl: ' ', textModel: '', visionModel: '').baseUri,
        isNull,
      );
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
      final v = VisionAnalyzer(client, () => config);
      final a = await v.analyze(Uint8List.fromList([1, 2, 3, 4]));
      expect(a.undertone, Undertone.cool);
      final sent = fake.requests.single;
      expect(sent['model'], 'llava');
      final msg = (sent['messages']! as List).single as Map;
      expect((msg['images'] as List).single, base64Encode([1, 2, 3, 4]));
    });

    test('an invalid model answer does not crash the analyzer', () async {
      fake.chatAnswer = 'I cannot help with that';
      final v = VisionAnalyzer(client, () => config);
      expect(v.analyze(Uint8List.fromList([1])), throwsA(isA<AiBadResponse>()));
    });

    test('huge or empty photos are rejected before any request', () async {
      final v = VisionAnalyzer(client, () => config);
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
      await VisionAnalyzer(client, () => config).analyzeFile(f);
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
      classifier = ProductClassifier(
        client,
        () => config,
        products,
        SafetyRepository(h),
      );
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
      fake = await FakeOllama.start(); // for tearDown
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
        () => config,
      );
    });
    tearDown(() => h.close());

    test(
      'the model receives the Beauty Profile, blacklist and product',
      () async {
        fake.chatAnswer = 'It suits you.';
        final out = await bot.reply(
          userId: 1,
          text: 'Подходит ли мне Сыворотка Niacinamide?',
          history: const [],
        );
        expect(out, 'It suits you.');
        final system =
            ((fake.requests.single['messages']! as List).first
                    as Map)['content']!
                as String;
        expect(system, contains('color type: Весна')); // demo profile
        expect(system, contains('skin concerns: Сухость и шелушение'));
        expect(system, contains('Парабены')); // enabled blacklist
        expect(system, contains('Niacinamide')); // the product in question
        expect(system, contains('ingredients:'));
        expect(system, contains('Never invent'));
        expect(system, contains('NOT a doctor'));
      },
    );

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
        fake = await FakeOllama.start();
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
      // system + at most 8 history + the question
      expect(
        msgs.length,
        lessThanOrEqualTo(1 + AssistantService.historyLimit + 1),
      );
      expect((msgs.last as Map)['content'], 'вопрос 5');
    });
  });
}
