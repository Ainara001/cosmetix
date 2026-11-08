/// What the user is told before anything personal is sent to the AI: who gets
/// it and how the provider may use it. Pure text, no state, so it can be tested.
/// Every sentence is its own key so `tr` can translate it; the functions take
/// the translator (`t`) and glue the sentences together.
///
/// The provider name is filled into `{provider}` OUTSIDE the translated
/// sentence, so the sentences stay translatable and the name stays the same in
/// RU/KZ/EN. The data-use facts are the Gemini API Additional Terms of Service
/// (effective 23 March 2026, https://ai.google.dev/gemini-api/terms): on the
/// free quota ("Unpaid Services") Google uses what is sent to improve its
/// products and human reviewers may read it; with a paid (billed) project it
/// does not use it for that and logs requests for a limited time to detect
/// abuse. For Claude the server does not declare a data-use policy, so the app
/// treats it as unknown. The server declares which one applies in /health
/// (`mode` = gemini/claude and `dataUse`).
class AiDisclosure {
  AiDisclosure._();

  /// Bump when the wording or the recipients change: everyone is asked again.
  static const consentVersion = 3;

  /// Human-readable provider name, filled into `{provider}`.
  static String providerLabel(String? mode) => switch (mode) {
    'gemini' => 'Google Gemini',
    'claude' => 'Anthropic Claude',
    _ => 'Gemini / Claude',
  };

  static const dataUsePaid =
      '{provider} не использует отправленное для улучшения своих продуктов; запросы хранятся ограниченное время только для выявления нарушений.';
  static const dataUseFree =
      'Сейчас сервер работает на бесплатном тарифе {provider}: {provider} может использовать отправленное для улучшения своих продуктов, и это могут просматривать люди.';
  static const dataUseUnknown =
      'Как {provider} использует отправленное, сервер не сообщил: считайте, что это может быть использовано и просмотрено людьми.';

  static const photoIntro =
      'Фото будет отправлено на сервер Cosmetix и через него в сервис {provider}, чтобы оценить цвет кожи. Приложение не сохраняет фото и удаляет его с телефона после анализа.';
  static const photoOutro =
      'Результат это подсказка, а не измерение и не диагноз. Согласие можно отозвать в Настройках.';

  static const chatIntro =
      'Ваши сообщения в чате будут отправляться на сервер Cosmetix и через него в сервис {provider}. Не пишите там личные данные.';
  static const chatOutro = 'Согласие можно отозвать в Настройках.';

  static const profileQuestion =
      'Разрешить ИИ видеть ваш Beauty-профиль и чёрный список, чтобы советы были точнее? Они будут отправлены на сервер Cosmetix и в {provider}. Фото и контакты не отправляются. Это можно изменить в Настройках.';

  static String _id(String s) => s;

  static String _fill(String text, String provider) =>
      text.replaceAll('{provider}', provider);

  /// How the provider may use what is sent, for [mode] = `paid`, `free` or
  /// anything else (unknown / not said), with the provider name filled in.
  static String dataUse(
    String? mode,
    String? provider, [
    String Function(String) t = _id,
  ]) =>
      _fill(
        t(switch (mode) {
          'paid' => dataUsePaid,
          'free' => dataUseFree,
          _ => dataUseUnknown,
        }),
        providerLabel(provider),
      );

  static String photoConsent(
    String? mode,
    String? provider, [
    String Function(String) t = _id,
  ]) =>
      '${_fill(t(photoIntro), providerLabel(provider))} ${dataUse(mode, provider, t)} ${t(photoOutro)}';

  static String chatConsent(
    String? mode,
    String? provider, [
    String Function(String) t = _id,
  ]) =>
      '${_fill(t(chatIntro), providerLabel(provider))} ${dataUse(mode, provider, t)} ${t(chatOutro)}';

  static String profileConsent(String? provider, [String Function(String) t = _id]) =>
      _fill(t(profileQuestion), providerLabel(provider));
}
