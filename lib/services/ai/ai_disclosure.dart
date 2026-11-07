/// What the user is told before anything personal is sent to the AI: who gets
/// it and how Google may use it. Pure text, no state, so it can be tested.
/// Every sentence is its own key so `tr` can translate it; the functions take
/// the translator (`t`) and glue the sentences together.
///
/// The facts come from the Gemini API Additional Terms of Service (effective
/// 23 March 2026, https://ai.google.dev/gemini-api/terms): on the free quota
/// ("Unpaid Services") Google uses what is sent to improve its products and
/// human reviewers may read it; with a paid (billed) project it does not use
/// it for that and logs requests for a limited time to detect abuse. The
/// server declares which one applies in /health (`dataUse`).
class AiDisclosure {
  AiDisclosure._();

  /// Bump when the wording or the recipients change: everyone is asked again.
  static const consentVersion = 2;

  static const dataUsePaid =
      'Google не использует отправленное для улучшения своих продуктов; запросы хранятся ограниченное время только для выявления нарушений.';
  static const dataUseFree =
      'Сейчас сервер работает на бесплатном тарифе Google: Google может использовать отправленное для улучшения своих продуктов, и это могут просматривать люди.';
  static const dataUseUnknown =
      'Как Google использует отправленное, сервер не сообщил: считайте, что это может быть использовано и просмотрено людьми.';

  static const photoIntro =
      'Фото будет отправлено на сервер Cosmetix и через него в сервис Google Gemini, чтобы оценить цвет кожи. Приложение не сохраняет фото и удаляет его с телефона после анализа.';
  static const photoOutro =
      'Результат это подсказка, а не измерение и не диагноз. Согласие можно отозвать в Настройках.';

  static const chatIntro =
      'Ваши сообщения в чате будут отправляться на сервер Cosmetix и через него в сервис Google Gemini. Не пишите там личные данные.';
  static const chatOutro = 'Согласие можно отозвать в Настройках.';

  static const profileQuestion =
      'Разрешить ИИ видеть ваш Beauty-профиль и чёрный список, чтобы советы были точнее? Они будут отправлены на сервер Cosmetix и в Google Gemini. Фото и контакты не отправляются. Это можно изменить в Настройках.';

  static String _id(String s) => s;

  /// How Google may use what is sent, for [mode] = `paid`, `free` or anything
  /// else (unknown / not said).
  static String dataUse(String? mode, [String Function(String) t = _id]) =>
      t(switch (mode) {
        'paid' => dataUsePaid,
        'free' => dataUseFree,
        _ => dataUseUnknown,
      });

  static String photoConsent(String? mode, [String Function(String) t = _id]) =>
      '${t(photoIntro)} ${dataUse(mode, t)} ${t(photoOutro)}';

  static String chatConsent(String? mode, [String Function(String) t = _id]) =>
      '${t(chatIntro)} ${dataUse(mode, t)} ${t(chatOutro)}';

  static String profileConsent([String Function(String) t = _id]) =>
      t(profileQuestion);
}
