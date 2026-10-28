import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/providers/ai_provider.dart';
import 'package:cosmetix/models/product.dart';
import 'package:cosmetix/providers/catalog_provider.dart';
import 'package:cosmetix/providers/chat_provider.dart';
import 'package:cosmetix/providers/settings_provider.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/services/assistant_service.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';
import 'package:cosmetix/widgets/product_art.dart';

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
    'Какой состав у палетки Flower Knows?',
    'Сравни цены Flower Knows и Peripera',
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
      showMessage(context, tr('Введите сообщение'), type: MessageType.warning);
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
                icon: const Icon(
                  Icons.delete_sweep_outlined,
                  color: AppColors.primaryDark,
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
              child: ListView.builder(
                controller: _scroll,
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
                      inputFormatters: [LengthLimitingTextInputFormatter(500)],
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
          for (final id in productIds) _ProductMiniCard(productId: id),
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
              decoration: const BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.smart_toy_outlined,
                size: 16,
                color: AppColors.primaryDark,
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
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primaryDark),
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
  };

  String get _hint => switch (failure) {
    AiFailure.rateLimited =>
      retryAfter == null
          ? tr('Попробуйте чуть позже.')
          : trf('Попробуйте через {n} с.', {'n': retryAfter}),
    AiFailure.notConfigured => tr(
      'Укажите его в Кабинет → Настройки → ИИ-ассистент.',
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
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 20,
            color: AppColors.primaryDark,
          ),
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
          if (failure != AiFailure.notConfigured)
            TextButton(onPressed: onRetry, child: Text(tr('Повторить'))),
        ],
      ),
    );
  }
}

/// A small tappable product card inside an assistant answer.
class _ProductMiniCard extends StatelessWidget {
  const _ProductMiniCard({required this.productId});

  final int productId;

  @override
  Widget build(BuildContext context) {
    final Product? p = context.watch<CatalogProvider>().byId(productId);
    // an id the model made up (or a product that is gone) shows nothing
    if (p == null) return const SizedBox.shrink();
    final pal = context.pal;
    final price = context.watch<SettingsProvider>().priceText(p.price);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: AppColors.blush,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () =>
              Navigator.pushNamed(context, AppRoutes.product, arguments: p.id),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  height: 52,
                  child: ProductArt(art: p.art, color: p.color, radius: 8),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.brand,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: pal.subtext),
                      ),
                      Text(
                        tr(p.name),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      Text(
                        price,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: p.hasDiscount ? AppColors.sale : pal.text,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: AppColors.primaryDark,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
