import 'package:flutter_test/flutter_test.dart';

import 'package:cosmetix/core/constants/legal_texts.dart';
import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/i18n/translations_en.dart';
import 'package:cosmetix/core/i18n/translations_kk.dart';
import 'package:cosmetix/providers/ai_provider.dart';
import 'package:cosmetix/services/ai/ai_disclosure.dart';

/// The privacy policy must say what the app really does: the optional AI
/// features send data to the Cosmetix server and through it to Google Gemini,
/// only after consent, only for users of the age the Gemini terms allow.
void main() {
  group('Russian (the source text)', () {
    const t = LegalTexts.privacy;

    test(
      'no longer claims that nothing is sent to a server or to third parties',
      () {
        expect(t, isNot(contains('не отправляет ваши данные на сервер')));
        expect(t, isNot(contains('не передаёт их третьим лицам')));
        expect(t, isNot(contains('только на вашем устройстве')));
      },
    );

    test('names the recipient, the data and the conditions', () {
      expect(t, contains('сервер Cosmetix'));
      expect(t, contains('Google Gemini'));
      expect(t, contains('Чат'));
      expect(t, contains('Beauty-профиль'));
      expect(t, contains('Фото'));
      expect(t, contains('Без вашего согласия ничего не отправляется'));
      expect(t, contains('отозвать согласие'));
    });

    test(
      'states the free-tier and paid-tier difference like the consent dialogs do',
      () {
        expect(t, contains('бесплатном тарифе'));
        expect(t, contains('просматривать люди'));
        expect(t, contains('платном тарифе'));
        expect(AiDisclosure.dataUseFree, contains('бесплатном тарифе'));
        expect(AiDisclosure.dataUsePaid, contains('не использует'));
      },
    );

    test('says that AI results are hints, not a diagnosis', () {
      expect(t, contains('не диагноз'));
    });

    test('the age in the policy is the age the app enforces', () {
      expect(AiProvider.minAge, 18);
      expect(t, contains('18 лет'));
    });
  });

  group('translations', () {
    test('English has the new policy, not the old one', () {
      final en = translationsEn[LegalTexts.privacy]!;
      expect(en, contains('Google Gemini'));
      expect(en, contains('18 or older'));
      expect(en, isNot(contains('does not send your data to a server')));
      expect(en, isNot(contains('does not share it with third parties')));
    });

    test(
      'Kazakh has no stale copy of the old claims: it falls back to Russian',
      () {
        expect(translationsKk[LegalTexts.privacy], isNull);
        currentLang = AppLang.kk;
        addTearDown(() => currentLang = AppLang.ru);
        expect(tr(LegalTexts.privacy), LegalTexts.privacy);
      },
    );

    test('the terms of use are untouched and still translated', () {
      expect(translationsEn[LegalTexts.terms], isNotNull);
      expect(translationsKk[LegalTexts.terms], isNotNull);
    });
  });
}
