import 'package:cosmetix/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/models/safety_models.dart';
import 'package:cosmetix/providers/safety_provider.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/common_widgets.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';

class BlacklistScreen extends StatefulWidget {
  const BlacklistScreen({super.key});

  @override
  State<BlacklistScreen> createState() => _BlacklistScreenState();
}

class _BlacklistScreenState extends State<BlacklistScreen> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final text = _controller.text.trim();
    if (!_formKey.currentState!.validate()) return;
    final error = await context.read<SafetyProvider>().addCustom(text);
    if (!mounted) return;
    if (error != null) {
      showMessage(context, error, type: MessageType.warning);
      return;
    }
    _controller.clear();
    FocusScope.of(context).unfocus();
    showMessage(
      context,
      trf('Компонент «{text}» добавлен в чёрный список', {'text': text}),
      type: MessageType.success,
    );
  }

  Future<void> _delete(BlacklistItem item) async {
    final ok = await confirmDialog(
      context,
      title: tr('Удалить из списка?'),
      message: trf('Компонент «{v0}» будет удалён из чёрного списка.', {
        'v0': tr(item.name),
      }),
      confirmLabel: tr('Удалить'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    await context.read<SafetyProvider>().deleteBlacklist(item);
  }

  @override
  Widget build(BuildContext context) {
    final safety = context.watch<SafetyProvider>();
    final pal = context.pal;

    return PageScaffold(
      title: tr('Чёрный список'),
      bigTitle: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(
            tr(
              'Отметьте компоненты, которых не должно быть в вашей косметике. Мы предупредим вас при анализе продукта.',
            ),
            style: AppTextStyles.small.copyWith(color: pal.subtext),
          ),
          const SizedBox(height: 12),
          Form(
            key: _formKey,
            child: TextFormField(
              controller: _controller,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _add(),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return tr('Введите название компонента');
                if (t.length < 2) return tr('Слишком короткое название');
                if (t.length > 40) {
                  return tr('Слишком длинное название (максимум 40)');
                }
                return null;
              },
              decoration: InputDecoration(
                hintText: tr('Добавить свой компонент...'),
                prefixIcon: const Icon(Icons.add, size: 20),
                suffixIcon: IconButton(
                  tooltip: tr('Добавить'),
                  icon: const Icon(
                    Icons.check_circle,
                    color: AppColors.primaryDark,
                  ),
                  onPressed: _add,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (safety.blacklist.isEmpty)
            EmptyState(
              icon: Icons.block,
              title: tr('Список пуст'),
              subtitle: tr('Добавьте компонент, которого хотите избегать'),
            ),
          for (final b in safety.blacklist)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr(b.name), style: AppTextStyles.bodyBold),
                          Text(
                            tr(b.description),
                            style: AppTextStyles.caption.copyWith(
                              color: pal.subtext,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (b.isCustom)
                      IconButton(
                        tooltip: tr('Удалить'),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => _delete(b),
                      ),
                    Switch(
                      value: b.enabled,
                      onChanged: (v) =>
                          context.read<SafetyProvider>().toggleBlacklist(b, v),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
