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
import 'package:cosmetix/services/ai/ai_config.dart';
import 'package:cosmetix/services/ai/ai_disclosure.dart';
import 'package:cosmetix/services/assistant_service.dart';
import 'package:cosmetix/services/recommendation_service.dart';

import 'ai_test.dart' show FakeAiProxy;

/// Nothing personal goes to the AI without an explicit, current consent that
/// names the recipient and how Google may use the data.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('what the user is told', () {
    test(
      'free tier: says plainly that Google may use it and people may read it',
      () {
        final t = AiDisclosure.photoConsent('free');
        expect(t, contains('Google Gemini'));
        expect(t, contains('бесплатном тарифе'));
        expect(t, contains('просматривать люди'));
        expect(t, contains('не диагноз'));
      },
    );

    test(
      'paid tier: says Google does not use it to improve products, and that it logs briefly',
      () {
        final t = AiDisclosure.photoConsent('paid');
        expect(t, contains('не использует'));
        expect(t, contains('ограниченное время'));
        expect(t, isNot(contains('бесплатном тарифе')));
      },
    );

    test('unknown or missing: assume the worst', () {
      for (final mode in [null, 'unknown', 'none', 'whatever']) {
        expect(AiDisclosure.photoConsent(mode), contains('считайте'));
      }
    });

    test(
      'every consent names Cosmetix and Google Gemini and promises a way out',
      () {
        for (final t in [
          AiDisclosure.photoConsent('paid'),
          AiDisclosure.chatConsent('paid'),
          AiDisclosure.profileConsent(),
        ]) {
          expect(t, contains('Cosmetix'));
          expect(t, contains('Google Gemini'));
          expect(t, contains('Настройках'));
        }
        expect(
          AiDisclosure.chatConsent('free'),
          contains('Не пишите там личные данные'),
        );
        expect(
          AiDisclosure.profileConsent(),
          contains('Фото и контакты не отправляются'),
        );
      },
    );

    test('the translator is applied to every sentence', () {
      final seen = <String>[];
      AiDisclosure.photoConsent('free', (s) {
        seen.add(s);
        return s.toUpperCase();
      });
      expect(
        seen,
        containsAll([
          AiDisclosure.photoIntro,
          AiDisclosure.dataUseFree,
          AiDisclosure.photoOutro,
        ]),
      );
    });
  });

  group('consent is stored with a version', () {
    late DatabaseHelper helper;
    late SettingsRepository repo;
    setUp(() {
      helper = DatabaseHelper(path: inMemoryDatabasePath);
      repo = SettingsRepository(helper);
    });
    tearDown(() => helper.close());

    AiProvider fresh() => AiProvider(
      repo,
      initial: const AiConfig(baseUrl: 'http://127.0.0.1:1'),
    );

    test('an old consent without a version no longer counts', () async {
      await repo.set('ai_share_photos', '1');
      await repo.set('ai_share_profile', '1');
      await repo.set('ai_profile_asked', '1');
      final ai = fresh();
      await ai.load();
      expect(ai.sharePhotos, isFalse);
      expect(ai.shareProfile, isFalse);
      expect(ai.profileAsked, isFalse);
      expect(ai.shareChat, isFalse);
      expect(ai.chatAsked, isFalse);
      // and the reset is written down, so it is not repeated
      final saved = await repo.all();
      expect(saved['ai_share_photos'], '0');
      expect(saved['ai_consent_version'], '${AiDisclosure.consentVersion}');
    });

    test('an older version is reset too', () async {
      await repo.set(
        'ai_consent_version',
        '${AiDisclosure.consentVersion - 1}',
      );
      await repo.set('ai_share_chat', '1');
      await repo.set('ai_chat_asked', '1');
      final ai = fresh();
      await ai.load();
      expect(ai.shareChat, isFalse);
      expect(ai.chatAsked, isFalse);
    });

    test('a consent given now survives a restart', () async {
      final a = fresh();
      await a.load();
      await a.setShareChat(true);
      await a.setSharePhotos(true);
      await a.setShareProfile(true);
      final b = fresh();
      await b.load();
      expect(b.shareChat, isTrue);
      expect(b.chatAsked, isTrue);
      expect(b.sharePhotos, isTrue);
      expect(b.shareProfile, isTrue);
    });

    test('a refusal is remembered as asked, not as consent', () async {
      final a = fresh();
      await a.load();
      await a.setShareChat(false);
      final b = fresh();
      await b.load();
      expect(b.chatAsked, isTrue);
      expect(b.shareChat, isFalse);
    });

    test('resetting the app forgets every consent', () async {
      final a = fresh();
      await a.load();
      await a.setShareChat(true);
      a.resetToDefaults();
      expect(a.shareChat, isFalse);
      expect(a.chatAsked, isFalse);
    });
  });

  group('the chat sends nothing without consent', () {
    late FakeAiProxy fake;
    late DatabaseHelper helper;
    setUp(() async {
      fake = await FakeAiProxy.start();
      helper = DatabaseHelper(path: inMemoryDatabasePath);
    });
    tearDown(() async {
      await fake.stop();
      await helper.close();
    });

    ChatProvider chat({required bool allowed}) {
      final ai = AiProvider(
        SettingsRepository(helper),
        initial: AiConfig(baseUrl: fake.url),
      )..ageSource = () => 30;
      final bot = AssistantService(
        RecommendationService(
          ProductRepository(helper),
          SafetyRepository(helper),
          UserRepository(helper),
        ),
        ai.client,
      );
      return ChatProvider(
        ChatRepository(helper),
        bot,
        chatAllowed: () => allowed,
      );
    }

    test(
      'no consent: no request, the message is not saved, the chat says why',
      () async {
        final c = chat(allowed: false);
        await c.load(1);
        final before = c.messages.length;
        await c.send('Привет');
        expect(fake.chatCalls, 0);
        expect(c.messages.length, before);
        expect(c.aiUnavailable, isTrue);
        expect(c.aiFailure, AiFailure.consentRequired);
      },
    );

    test('with consent it goes through', () async {
      fake.chatAnswer = 'Здравствуйте!';
      final c = chat(allowed: true);
      await c.load(1);
      await c.send('Привет');
      expect(fake.chatCalls, 1);
      expect(c.aiUnavailable, isFalse);
      expect(c.messages.last.text, 'Здравствуйте!');
    });
  });
}
