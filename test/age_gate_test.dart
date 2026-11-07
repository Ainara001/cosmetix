import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:cosmetix/database/database_helper.dart';
import 'package:cosmetix/providers/ai_provider.dart';
import 'package:cosmetix/providers/chat_provider.dart';
import 'package:cosmetix/repositories/chat_repository.dart';
import 'package:cosmetix/repositories/product_repository.dart';
import 'package:cosmetix/repositories/safety_repository.dart';
import 'package:cosmetix/repositories/settings_repository.dart';
import 'package:cosmetix/repositories/user_repository.dart';
import 'package:cosmetix/services/ai/ai_client.dart';
import 'package:cosmetix/services/ai/ai_config.dart';
import 'package:cosmetix/services/assistant_service.dart';
import 'package:cosmetix/services/recommendation_service.dart';

import 'ai_test.dart' show FakeAiProxy;

/// The Gemini API terms do not allow an app that may be used by people under
/// 18, and Cosmetix has no age check at sign-up: the remote AI is available only
/// to a user whose stated age is at least 18. Real HTTP to a fake proxy, so no
/// widget tests in this file (see age_gate_ui_test.dart).
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late FakeAiProxy fake;
  setUp(() async => fake = await FakeAiProxy.start());
  tearDown(() => fake.stop());

  AiProvider provider({int? age, bool wired = true}) {
    final ai = AiProvider(
      SettingsRepository(DatabaseHelper(path: inMemoryDatabasePath)),
      initial: AiConfig(baseUrl: fake.url),
    );
    if (wired) ai.ageSource = () => age;
    return ai;
  }

  group('AiProvider age rule', () {
    test('18 and over are allowed, 17 and unknown are not', () {
      expect(provider(age: 18).ageAllowed, isTrue);
      expect(provider(age: 45).ageAllowed, isTrue);
      expect(provider(age: 17).ageAllowed, isFalse);
      expect(provider(age: 12).ageAllowed, isFalse);
      expect(provider(age: 0).ageAllowed, isFalse);
      expect(provider(age: null).ageAllowed, isFalse);
    });

    test('unknown is told apart from too young', () {
      expect(provider(age: null).ageUnknown, isTrue);
      expect(provider(age: 17).ageUnknown, isFalse);
      expect(provider(age: 30).ageUnknown, isFalse);
    });

    test('no age source wired means nobody is allowed (the safe default)', () {
      final ai = provider(wired: false);
      expect(ai.ageAllowed, isFalse);
      expect(ai.ageUnknown, isTrue);
    });

    test('a change of the profile age reaches the screens', () {
      var age = 15;
      final ai = provider()..ageSource = () => age;
      var notified = 0;
      ai.addListener(() => notified++);
      expect(ai.ageAllowed, isFalse);
      age = 19;
      ai.ageChanged();
      expect(notified, 1);
      expect(ai.ageAllowed, isTrue);
    });
  });

  group('the client is the one gate', () {
    const msg = [AiMessage('user', 'Привет')];

    test(
      'a minor: nothing is sent, the request never reaches the proxy',
      () async {
        final ai = provider(age: 16);
        await expectLater(
          ai.client.chat(messages: msg),
          throwsA(isA<AiNotAllowed>()),
        );
        expect(fake.chatCalls, 0);
      },
    );

    test('an unknown age is refused the same way', () async {
      final ai = provider(age: null);
      await expectLater(
        ai.client.chat(messages: msg),
        throwsA(isA<AiNotAllowed>()),
      );
      expect(fake.chatCalls, 0);
    });

    test('a photo request is refused before it is sent', () async {
      final ai = provider(age: 16);
      await expectLater(
        ai.client.chat(
          messages: const [
            AiMessage('user', 'x', images: ['/9j/AAAA']),
          ],
        ),
        throwsA(isA<AiNotAllowed>()),
      );
      expect(fake.chatCalls, 0);
    });

    test('an adult goes through', () async {
      fake.chatAnswer = 'Привет!';
      final ai = provider(age: 25);
      final r = await ai.client.chat(messages: msg);
      expect(r.text, 'Привет!');
      expect(fake.chatCalls, 1);
    });

    test('the age is read on every call: becoming 18 opens the gate', () async {
      fake.chatAnswer = 'ok';
      var age = 17;
      final ai = provider()..ageSource = () => age;
      await expectLater(
        ai.client.chat(messages: msg),
        throwsA(isA<AiNotAllowed>()),
      );
      age = 18;
      expect((await ai.client.chat(messages: msg)).text, 'ok');
      expect(fake.chatCalls, 1);
    });

    test('the health check carries no user content and is not gated', () async {
      final ai = provider(age: 16);
      final h = await ai.client.health();
      expect(h.mode, isNotEmpty);
    });

    test(
      'a client built without a gate (tests, tools) works as before',
      () async {
        fake.chatAnswer = 'x';
        final plain = AiClient(() => AiConfig(baseUrl: fake.url));
        expect((await plain.chat(messages: msg)).text, 'x');
      },
    );
  });

  test(
    'the chat tells a minor about the age limit and sends nothing',
    () async {
      final h = DatabaseHelper(path: inMemoryDatabasePath);
      addTearDown(h.close);
      final ai = provider(age: 15);
      final bot = AssistantService(
        RecommendationService(
          ProductRepository(h),
          SafetyRepository(h),
          UserRepository(h),
        ),
        ai.client,
      );
      final chat = ChatProvider(ChatRepository(h), bot);
      await chat.load(1);
      await chat.send('Привет');
      expect(chat.aiUnavailable, isTrue);
      expect(chat.aiFailure, AiFailure.ageRestricted);
      expect(fake.chatCalls, 0);
    },
  );
}
