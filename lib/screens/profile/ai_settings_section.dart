import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/providers/ai_provider.dart';
import 'package:cosmetix/providers/auth_provider.dart';
import 'package:cosmetix/providers/catalog_provider.dart';
import 'package:cosmetix/services/ai/product_classifier.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/custom_button.dart';

/// Settings -> AI assistant: where the Ollama server is, which models are
/// used, whether it answers, plus a one-time product classification.
/// Everything outside the chat / photo analysis works without it.
class AiSettingsSection extends StatefulWidget {
  const AiSettingsSection({super.key});

  @override
  State<AiSettingsSection> createState() => _AiSettingsSectionState();
}

class _AiSettingsSectionState extends State<AiSettingsSection> {
  bool _classifying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ai = context.read<AiProvider>();
      if (ai.status == AiStatus.unknown && ai.isConfigured) {
        ai.testConnection();
      }
    });
  }

  Future<void> _edit() async {
    final ai = context.read<AiProvider>();
    final url = TextEditingController(text: ai.config.baseUrl);
    final text = TextEditingController(text: ai.config.textModel);
    final vision = TextEditingController(text: ai.config.visionModel);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Сервер ИИ (Ollama)')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: url,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: tr('Адрес сервера'),
                  hintText: 'http://192.168.1.50:11434',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: text,
                autocorrect: false,
                decoration: InputDecoration(labelText: tr('Текстовая модель')),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: vision,
                autocorrect: false,
                decoration: InputDecoration(labelText: tr('Модель для фото')),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Отмена')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Сохранить')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ai.update(
      baseUrl: url.text,
      textModel: text.text,
      visionModel: vision.text,
    );
    await ai.testConnection();
  }

  Future<void> _classify() async {
    final ai = context.read<AiProvider>();
    final classifier = context.read<ProductClassifier>();
    final catalog = context.read<CatalogProvider>();
    final userId = context.read<AuthProvider>().userId;
    setState(() => _classifying = true);
    try {
      final r = await classifier.classifyPending(userId);
      await catalog.refreshPersonalization();
      if (!mounted) return;
      if (r.stoppedOffline) {
        ai.markOffline('The AI server stopped answering');
        showMessage(
          context,
          tr('ИИ-сервер недоступен. Попробуйте позже.'),
          type: MessageType.warning,
        );
      } else if (r.classified == 0 && r.failed == 0) {
        showMessage(
          context,
          tr('Все товары уже классифицированы'),
          type: MessageType.info,
        );
      } else {
        showMessage(
          context,
          trf('Классифицировано товаров: {n}', {'n': r.classified}),
          type: r.failed == 0 ? MessageType.success : MessageType.warning,
        );
      }
    } finally {
      if (mounted) setState(() => _classifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final ai = context.watch<AiProvider>();
    final (statusText, statusColor) = switch (ai.status) {
      AiStatus.online => (tr('Подключено'), AppColors.success),
      AiStatus.checking => (tr('Проверка…'), pal.subtext),
      AiStatus.offline => (
        ai.isConfigured ? tr('Недоступно') : tr('Адрес не задан'),
        AppColors.sale,
      ),
      AiStatus.unknown => (tr('Не проверено'), pal.subtext),
    };

    Widget row(String label, String value, {Color? color}) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: AppTextStyles.small.copyWith(color: pal.subtext),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: AppTextStyles.bodyBold.copyWith(color: color),
            ),
          ),
        ],
      ),
    );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row(tr('Статус'), statusText, color: statusColor),
          row(tr('Сервер'), ai.config.displayHost),
          row(tr('Текстовая модель'), ai.config.textModel),
          row(tr('Модель для фото'), ai.config.visionModel),
          if (ai.status == AiStatus.online && !ai.textModelInstalled)
            Text(
              tr('Текстовая модель не установлена на сервере.'),
              style: AppTextStyles.caption.copyWith(color: AppColors.sale),
            ),
          if (ai.status == AiStatus.online && !ai.visionModelInstalled)
            Text(
              tr('Модель для фото не установлена на сервере.'),
              style: AppTextStyles.caption.copyWith(color: AppColors.sale),
            ),
          if (ai.status == AiStatus.offline && ai.detail != null)
            Text(
              ai.detail!,
              style: AppTextStyles.caption.copyWith(color: pal.subtext),
            ),
          const SizedBox(height: 10),
          Text(
            tr(
              'Без ИИ работают тест, каталог, чёрный список и рекомендации. ИИ нужен для чата, анализа фото и уточнения подбора.',
            ),
            style: AppTextStyles.caption.copyWith(color: pal.subtext),
          ),
          const SizedBox(height: 12),
          CustomButton(
            label: tr('Проверить подключение'),
            icon: Icons.wifi_tethering,
            loading: ai.status == AiStatus.checking,
            onPressed: ai.testConnection,
          ),
          const SizedBox(height: 8),
          CustomButton(
            label: tr('Изменить сервер и модели'),
            outlined: true,
            onPressed: _edit,
          ),
          const SizedBox(height: 8),
          CustomButton(
            label: tr('Классифицировать товары (ИИ)'),
            outlined: true,
            loading: _classifying,
            onPressed: ai.isOnline ? _classify : null,
          ),
        ],
      ),
    );
  }
}
