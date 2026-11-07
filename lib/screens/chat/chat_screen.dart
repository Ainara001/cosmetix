import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/providers/ai_provider.dart';
import 'package:cosmetix/providers/catalog_provider.dart';
import 'package:cosmetix/providers/chat_provider.dart';
import 'package:cosmetix/services/assistant_service.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';
import 'package:cosmetix/widgets/product_mini_card.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  static const _suggestions = [
    'Есть скидки?',
    'Посоветуй тинт для губ',
    'Что подойдёт моему цветотипу?',
    'Где есть ниацинамид?',
    'Где купить Niacinamide рядом со мной?',
    'Есть альтернативы подешевле рядом?',
    'Какой состав у крема CeraVe?',
    'Сравни цены Rom&nd и Peripera',
  ];

  @override
  void initState() {
    super.initState();
    // learn whether the proxy talks to a real model or is in test mode
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ai = context.read<AiProvider>();
      if (ai.status == AiStatus.unknown && ai.isConfigured) {
        ai.testConnection();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _wait() => showMessage(
    context,
    tr('Помощник ещё отвечает, подождите секунду'),
    type: MessageType.info,
  );

  Future<void> _send([String? text]) async {
    final value = (text ?? _controller.text).trim();
    if (value.isEmpty) {
      // nothing to send: the button just puts the keyboard away
      FocusManager.instance.primaryFocus?.unfocus();
      return;
    }
    if (value.length > 500) {
      showMessage(
        context,
        tr('Сообщение слишком длинное (максимум 500 символов)'),
        type: MessageType.warning,
      );
      return;
    }
    final ai = context.read<AiProvider>();
    if (!ai.ageAllowed) {
      // the Gemini API terms: no remote AI for under-18s or an unknown age;
      // nothing is typed away and nothing is sent
      FocusManager.instance.primaryFocus?.unfocus();
      showMessage(
        context,
        ai.ageUnknown
            ? tr(
                'ИИ-помощник доступен с 18 лет. Укажите год рождения в профиле.',
              )
            : tr('ИИ-помощник доступен с 18 лет.'),
        type: MessageType.warning,
      );
      return;
    }
    if (!ai.profileAsked) {
      // privacy: the Beauty profile and blacklist leave the phone only if the
      // user agrees (asked once, can be changed in Settings)
      final ok = await confirmDialog(
        context,
        title: tr('Учитывать ваши данные?'),
        message: tr(
          'Разрешить ИИ видеть ваш Beauty-профиль и чёрный список, чтобы советы были точнее? Они будут отправлены на сервер ИИ. Фото и контакты не отправляются. Это можно изменить в Настройках.',
        ),
        confirmLabel: tr('Разрешить'),
      );
      if (!mounted) return;
      await ai.setShareProfile(ok);
      if (!mounted) return;
    }
    _controller.clear();
    final chat = context.read<ChatProvider>();
    final future = chat.send(value);
    _scrollDown();
    await future;
    _scrollDown();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final ai = context.watch<AiProvider>();
    final pal = context.pal;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Container(
          color: isDark ? pal.background : const Color(0xFFF9EEF1),
          child: Column(
            children: [
              BackTitleBar(
                title: tr('ИИ-помощник'),
                bigTitle: true,
                showBack: false,
                trailing: IconButton(
                  tooltip: tr('Очистить чат'),
                  icon: Icon(
                    Icons.delete_sweep_outlined,
                    color: context.pal.accent,
                  ),
                  onPressed: () async {
                    final ok = await confirmDialog(
                      context,
                      title: tr('Очистить переписку?'),
                      message: tr('Все сообщения будут удалены.'),
                      confirmLabel: tr('Очистить'),
                      destructive: true,
                    );
                    if (ok && context.mounted) {
                      await context.read<ChatProvider>().clear();
                    }
                  },
                ),
              ),
              if (ai.isMock)
                _InfoBanner(
                  icon: Icons.science_outlined,
                  text: tr(
                    'Тестовый режим: ключ ИИ на сервере не задан, ответы ненастоящие.',
                  ),
                ),
              Expanded(
                // a tap on the conversation or a drag puts the keyboard away
                child: ListView.builder(
                  controller: _scroll,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  itemCount: chat.messages.length + (chat.typing ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i >= chat.messages.length) {
                      return _Bubble(
                        text: tr('Печатаю…'),
                        isUser: false,
                        faded: true,
                      );
                    }
                    final m = chat.messages[i];
                    if (m.isUser) return _Bubble(text: m.text, isUser: true);
                    // the assistant marks catalog products as [#id]: show the
                    // text without markers and a tappable card per product
                    final parsed = AssistantService.parseReply(m.text);
                    return _Bubble(
                      text: tr(parsed.text),
                      isUser: false,
                      productIds: parsed.productIds,
                    );
                  },
                ),
              ),
              if (chat.aiUnavailable)
                _OfflineBanner(
                  failure: chat.aiFailure ?? AiFailure.unavailable,
                  retryAfter: chat.retryAfter,
                  onRetry: () => context.read<ChatProvider>().retry(),
                ),
              if (context.watch<CatalogProvider>().hasProfile &&
                  !ai.shareProfile)
                _ShareProfileBanner(onAllow: () => ai.setShareProfile(true)),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => ActionChip(
                    label: Text(
                      tr(_suggestions[i]),
                      style: const TextStyle(fontSize: 12),
                    ),
                    backgroundColor: pal.surface,
                    side: BorderSide(color: pal.border),
                    onPressed: chat.typing
                        ? _wait
                        : () => _send(tr(_suggestions[i])),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        minLines: 1,
                        maxLines: 3,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(500),
                        ],
                        decoration: InputDecoration(
                          hintText: tr('Спросите про цены, состав, скидки...'),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: tr('Отправить'),
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.primary,
                      ),
                      onPressed: chat.typing ? _wait : _send,
                      icon: const Icon(Icons.send_rounded, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.text,
    required this.isUser,
    this.faded = false,
    this.productIds = const [],
  });

  final String text;
  final bool isUser;
  final bool faded;

  /// Catalog products the answer mentions (shown as cards under the text).
  final List<int> productIds;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.72,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isUser ? const Color(0xFFEBD8D3) : pal.surface,
        borderRadius: BorderRadius.circular(16),
        border: isUser ? null : Border.all(color: pal.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.35,
              color: faded
                  ? pal.subtext
                  : (isUser ? const Color(0xFF1E1A1C) : pal.text),
            ),
          ),
          for (final id in productIds) ProductMiniCard(productId: id),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: context.pal.pinkSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.smart_toy_outlined,
                size: 16,
                color: context.pal.accent,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(child: bubble),
        ],
      ),
    );
  }
}

/// The Beauty Test is done but the AI may not use it: one tap to allow.
class _ShareProfileBanner extends StatelessWidget {
  const _ShareProfileBanner({required this.onAllow});

  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: context.pal.pinkSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 18, color: context.pal.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr(
                'ИИ не видит результаты вашего теста, поэтому советы по цветотипу и коже будут общими.',
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          TextButton(onPressed: onAllow, child: Text(tr('Разрешить'))),
        ],
      ),
    );
  }
}

/// A small note above the messages (for example the AI test mode).
class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.pal.pinkSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: context.pal.accent),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}

/// Shown when the AI did not answer: the chat itself keeps working (history,
/// input), only the answer is missing.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({
    required this.failure,
    required this.onRetry,
    this.retryAfter,
  });

  final AiFailure failure;
  final int? retryAfter;
  final VoidCallback onRetry;

  String get _title => switch (failure) {
    AiFailure.rateLimited => tr('ИИ-помощник перегружен или лимит исчерпан'),
    AiFailure.timeout => tr('ИИ-помощник не успел ответить'),
    AiFailure.notConfigured => tr('Адрес сервера ИИ не задан'),
    AiFailure.unavailable => tr('ИИ-помощник сейчас недоступен'),
    AiFailure.ageRestricted => tr('ИИ-помощник доступен с 18 лет'),
  };

  String get _hint => switch (failure) {
    AiFailure.rateLimited =>
      retryAfter == null
          ? tr('Попробуйте чуть позже.')
          : trf('Попробуйте через {n} с.', {'n': retryAfter}),
    AiFailure.notConfigured => tr(
      'Укажите его в Кабинет → Настройки → ИИ-ассистент.',
    ),
    AiFailure.ageRestricted => tr(
      'Укажите год рождения в профиле. Остальные функции работают.',
    ),
    _ => tr('Остальные функции приложения работают.'),
  };

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: context.pal.pinkSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 20, color: context.pal.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  _hint,
                  style: TextStyle(fontSize: 11.5, color: pal.subtext),
                ),
              ],
            ),
          ),
          if (failure != AiFailure.notConfigured &&
              failure != AiFailure.ageRestricted)
            TextButton(onPressed: onRetry, child: Text(tr('Повторить'))),
        ],
      ),
    );
  }
}
