import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/providers/chat_provider.dart';
import 'package:cosmetix/providers/nav_provider.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';

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
    final pal = context.pal;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: Container(
        color: isDark ? pal.background : const Color(0xFFF9EEF1),
        child: Column(
          children: [
            Container(
              color: pal.surface,
              child: BackTitleBar(
                title: tr('ИИ-помощник'),
                bigTitle: true,
                onBack: () =>
                    context.read<NavProvider>().setTab(NavProvider.home),
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
                  return _Bubble(
                    text: m.isUser ? m.text : tr(m.text),
                    isUser: m.isUser,
                  );
                },
              ),
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
  const _Bubble({required this.text, required this.isUser, this.faded = false});

  final String text;
  final bool isUser;
  final bool faded;

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
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13.5,
          height: 1.35,
          color: faded
              ? pal.subtext
              : (isUser ? const Color(0xFF1E1A1C) : pal.text),
        ),
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
