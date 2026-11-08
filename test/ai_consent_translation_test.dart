import 'package:flutter_test/flutter_test.dart';

import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/services/ai/ai_disclosure.dart';

/// The consent dialogs and every distinct "AI is unavailable" reason must be
/// fully translated in EN and KK: `tr` must NOT fall back to the Russian source.
///
/// These strings are not reachable by the `language_test.dart` screen walk
/// (consent dialogs open only after a user action, and the offline banner only
/// after a failed AI call), so they are pinned here explicitly.
void main() {
  // Consent disclosure as it exists in `origin/main` (Google Gemini wording).
  final disclosureGoogle = <String>[
    AiDisclosure.dataUsePaid,
    AiDisclosure.dataUseFree,
    AiDisclosure.dataUseUnknown,
    AiDisclosure.photoIntro,
    AiDisclosure.photoOutro,
    AiDisclosure.chatIntro,
    AiDisclosure.chatOutro,
    AiDisclosure.profileQuestion,
  ];

  // One clear reason per AI failure on the photo-analysis screen
  // (`BeautyPhotoScreen._friendly`).
  final photoReasons = <String>[
    'ИИ-сервер недоступен.',
    'ИИ отвечает слишком долго.',
    'ИИ перегружен или лимит исчерпан. Попробуйте позже.',
    'Анализ по фото доступен с 18 лет.',
    'Анализ по фото сейчас отключён.',
    'ИИ вернул ошибку. Попробуйте ещё раз позже.',
    'Не удалось разобрать ответ ИИ.',
  ];

  // One clear reason per failure in the chat (`_OfflineBanner._title`).
  final chatReasons = <String>[
    'ИИ-помощник перегружен или лимит исчерпан',
    'ИИ-помощник не успел ответить',
    'Адрес сервера ИИ не задан',
    'ИИ-помощник сейчас недоступен',
    'ИИ-помощник доступен с 18 лет',
    'Нужно согласие на отправку сообщений в ИИ',
  ];

  // Age gates and consent switches on the AI settings screen, as written in
  // `origin/main` (Google Gemini wording).
  final ageAndSettings = <String>[
    'Функции ИИ доступны с 18 лет.',
    'Функции ИИ доступны с 18 лет. Укажите год рождения в профиле.',
    'Функции ИИ доступны с 18 лет. Укажите год рождения в профиле, чтобы их включить.',
    'Уточнение с помощью ИИ доступно с 18 лет. Укажите год рождения в профиле.',
    'ИИ-помощник доступен с 18 лет. Укажите год рождения в профиле.',
    'ИИ-помощник доступен с 18 лет.',
    'Укажите год рождения в профиле. Тест работает и без фото, по вашим ответам.',
    'Тест работает и без фото, по вашим ответам.',
    'Сервер отключил анализ по фото: фото не отправляются.',
    'Анализ по фото сейчас отключён. Тест работает по вашим ответам, фото не нужно.',
    'Укажите год рождения в профиле. Остальные функции работают.',
    'Включите его в Кабинет → Настройки → ИИ-ассистент.',
    'Отправлять ИИ сообщения чата',
    'Отправлять ИИ Beauty-профиль и чёрный список',
    'Разрешить отправку фото в ИИ',
    'Отправлять сообщения в ИИ?',
    'Без согласия на отправку сообщений ИИ-чат не отвечает. Включить можно в Настройках.',
  ];

  // Strings that exist only in the wording of PR #43 (provider-neutral `{provider}`
  // and "выбранный сервис ИИ"). They must be translated in Kazakh NOW so Kazakh
  // stays translated the moment #43 lands; the English side arrives with #43 itself.
  final kkForwardLooking = <String>[
    // Shown on origin/main; PR #43 replaces it (and drops its English entry),
    // so only Kazakh is pinned here to stay valid in either merge order.
    'Данные уходят на сервер Cosmetix и в Google Gemini только после вашего согласия.',
    '{provider} не использует отправленное для улучшения своих продуктов; запросы хранятся ограниченное время только для выявления нарушений.',
    'Сейчас сервер работает на бесплатном тарифе {provider}: {provider} может использовать отправленное для улучшения своих продуктов, и это могут просматривать люди.',
    'Как {provider} использует отправленное, сервер не сообщил: считайте, что это может быть использовано и просмотрено людьми.',
    'Фото будет отправлено на сервер Cosmetix и через него в сервис {provider}, чтобы оценить цвет кожи. Приложение не сохраняет фото и удаляет его с телефона после анализа.',
    'Ваши сообщения в чате будут отправляться на сервер Cosmetix и через него в сервис {provider}. Не пишите там личные данные.',
    'Разрешить ИИ видеть ваш Beauty-профиль и чёрный список, чтобы советы были точнее? Они будут отправлены на сервер Cosmetix и в {provider}. Фото и контакты не отправляются. Это можно изменить в Настройках.',
    'Данные уходят на сервер Cosmetix и в выбранный сервис ИИ только после вашего согласия.',
  ];

  final shared = <String>[
    ...disclosureGoogle,
    ...photoReasons,
    ...chatReasons,
    ...ageAndSettings,
  ];

  test('en: consent and AI-unavailable strings are translated', () {
    currentLang = AppLang.en;
    addTearDown(() => currentLang = AppLang.ru);
    final missing = [
      for (final key in shared)
        if (tr(key) == key) key,
    ];
    expect(missing, isEmpty, reason: 'fell back to Russian in en');
  });

  test('kk: consent and AI-unavailable strings are translated', () {
    currentLang = AppLang.kk;
    addTearDown(() => currentLang = AppLang.ru);
    final missing = [
      for (final key in [...shared, ...kkForwardLooking])
        if (tr(key) == key) key,
    ];
    expect(missing, isEmpty, reason: 'fell back to Russian in kk');
  });

  for (final lang in [AppLang.en, AppLang.kk]) {
    test('${lang.code}: every photo-analysis failure has its own text', () {
      currentLang = lang;
      addTearDown(() => currentLang = AppLang.ru);
      final texts = {for (final key in photoReasons) tr(key)};
      expect(texts.length, photoReasons.length);
    });

    test('${lang.code}: every chat failure has its own text', () {
      currentLang = lang;
      addTearDown(() => currentLang = AppLang.ru);
      final texts = {for (final key in chatReasons) tr(key)};
      expect(texts.length, chatReasons.length);
    });
  }
}
