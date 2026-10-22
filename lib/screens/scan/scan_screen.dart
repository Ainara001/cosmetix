import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/providers/safety_provider.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/services/ingredient_scan/ingredient_matcher.dart';
import 'package:cosmetix/services/ingredient_scan/ingredient_ocr.dart';
import 'package:cosmetix/services/ingredient_scan/ingredient_text_parser.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/common_widgets.dart';
import 'package:cosmetix/widgets/custom_button.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';

/// "Проверка состава": photo of an ingredient list -> text on the phone ->
/// the user checks and fixes the list -> comparison with the personal
/// blacklist, with an explanation for every hit.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _text = TextEditingController();
  String? _photo;
  bool _reading = false;
  String? _notice;
  List<String>? _checked;
  List<ScanMatch> _matches = const [];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool camera}) async {
    final source = context.read<ScanPhotoSource>();
    final ocr = context.read<IngredientOcr>();
    String? path;
    try {
      path = await source.pick(camera: camera);
    } on PhotoUnavailable {
      if (!mounted) return;
      showMessage(
        context,
        camera
            ? tr(
                'Камера недоступна (в симуляторе камеры нет). Выберите фото из галереи или введите состав вручную.',
              )
            : tr('Не удалось открыть галерею. Проверьте доступ к фото.'),
        type: MessageType.error,
      );
      return;
    }
    if (path == null || !mounted) return;
    setState(() {
      _photo = path;
      _reading = true;
      _notice = null;
      _checked = null;
    });
    try {
      final raw = await ocr.recognize(path);
      if (!mounted) return;
      final items = IngredientTextParser.parse(raw);
      setState(() {
        _reading = false;
        if (items.isEmpty) {
          _notice = tr(
            'Не удалось прочитать состав на фото. Попробуйте сфотографировать ближе и при хорошем освещении или введите состав вручную.',
          );
        } else {
          _text.text = IngredientTextParser.join(items);
          _notice = tr(
            'Состав распознан. Проверьте список: распознавание может ошибаться.',
          );
        }
      });
    } on OcrUnavailable {
      if (!mounted) return;
      setState(() {
        _reading = false;
        _notice = tr(
          'Распознавание текста недоступно на этом устройстве. Введите состав вручную.',
        );
      });
    }
  }

  void _check() {
    final items = IngredientTextParser.parse(_text.text);
    if (items.isEmpty) {
      showMessage(
        context,
        tr('Введите состав или выберите фото'),
        type: MessageType.warning,
      );
      return;
    }
    final blacklist = context.read<SafetyProvider>().blacklist;
    setState(() {
      _checked = items;
      _matches = IngredientMatcher.match(items, blacklist);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final safety = context.watch<SafetyProvider>();
    final hasActive = safety.blacklist.any((b) => b.enabled);

    return PageScaffold(
      title: tr('Проверка состава'),
      bigTitle: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          AppCard(
            color: AppColors.primarySoft,
            borderColor: Colors.transparent,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 18,
                  color: AppColors.primaryDark,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr(
                      'Сфотографируйте состав на упаковке или выберите фото. Текст читается на телефоне: фото никуда не отправляется и не сохраняется.',
                    ),
                    style: AppTextStyles.small,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          CustomButton(
            label: tr('Выбрать фото из галереи'),
            icon: Icons.photo_library_outlined,
            loading: _reading,
            onPressed: () => _pick(camera: false),
          ),
          const SizedBox(height: 10),
          CustomButton(
            label: tr('Сделать снимок'),
            icon: Icons.photo_camera_outlined,
            outlined: true,
            onPressed: _reading ? null : () => _pick(camera: true),
          ),
          if (_photo != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 150,
                width: double.infinity,
                child: Image.file(
                  File(_photo!),
                  fit: BoxFit.cover,
                  cacheWidth: 900,
                  errorBuilder: (_, _, _) => const SizedBox(),
                ),
              ),
            ),
          ],
          if (_reading)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                tr('Читаю текст на фото…'),
                style: AppTextStyles.small.copyWith(color: pal.subtext),
              ),
            ),
          if (_notice != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _notice!,
                style: AppTextStyles.small.copyWith(color: pal.subtext),
              ),
            ),
          SectionTitle(tr('Состав (проверьте и исправьте)')),
          TextField(
            controller: _text,
            minLines: 4,
            maxLines: 10,
            maxLength: 3000,
            decoration: InputDecoration(
              hintText: tr('Aqua, Glycerin, Dimethicone, Parfum…'),
              helperText: tr('Компоненты разделяйте запятыми.'),
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: 10),
          CustomButton(
            label: tr('Проверить по чёрному списку'),
            icon: Icons.fact_check_outlined,
            onPressed: _check,
          ),
          if (_checked != null) ..._results(context, hasActive),
        ],
      ),
    );
  }

  List<Widget> _results(BuildContext context, bool hasActive) {
    final pal = context.pal;
    final items = _checked!;
    final hitNames = {for (final m in _matches) m.ingredient};
    return [
      SectionTitle(tr('Результат')),
      if (!hasActive)
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(
                  'В чёрном списке нет включённых компонентов, поэтому сравнивать не с чем.',
                ),
                style: AppTextStyles.small,
              ),
              const SizedBox(height: 8),
              LinkText(
                tr('Открыть чёрный список'),
                onTap: () => Navigator.pushNamed(context, AppRoutes.blacklist),
              ),
            ],
          ),
        )
      else
        AppCard(
          color: _matches.isEmpty ? AppColors.successSoft : AppColors.saleSoft,
          borderColor: Colors.transparent,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _matches.isEmpty
                    ? Icons.check_circle_outline
                    : Icons.warning_amber_rounded,
                color: _matches.isEmpty ? AppColors.success : AppColors.sale,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _matches.isEmpty
                      ? tr('Совпадений с вашим чёрным списком не найдено.')
                      : trf('Найдено совпадений с чёрным списком: {n}', {
                          'n': _matches.length,
                        }),
                  style: AppTextStyles.bodyBold,
                ),
              ),
            ],
          ),
        ),
      for (final m in _matches)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: AppCard(
            borderColor: AppColors.sale,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.ingredient, style: AppTextStyles.bodyBold),
                const SizedBox(height: 4),
                Text(
                  m.reason == ScanMatchReason.group
                      ? trf(
                          '«{v0}» относится к группе «{v1}», которую вы внесли в чёрный список.',
                          {'v0': m.ingredient, 'v1': tr(m.item.name)},
                        )
                      : trf(
                          'В названии есть компонент «{v1}», который вы добавили в чёрный список.',
                          {'v1': m.item.name},
                        ),
                  style: AppTextStyles.small,
                ),
                if (m.item.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      tr(m.item.description),
                      style: AppTextStyles.caption.copyWith(color: pal.subtext),
                    ),
                  ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 12),
      Text(
        trf('Все компоненты ({n})', {'n': items.length}),
        style: AppTextStyles.subtitle,
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final i in items)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: hitNames.contains(i) ? AppColors.saleSoft : pal.field,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                i,
                style: TextStyle(
                  fontSize: 12,
                  color: hitNames.contains(i) ? AppColors.sale : pal.text,
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 12),
      Text(
        tr(
          'Проверка идёт только по вашему чёрному списку и по известным названиям компонентов, редкие названия она может пропустить. Это не гарантия отсутствия аллергии и не медицинское заключение.',
        ),
        style: AppTextStyles.caption.copyWith(color: pal.subtext),
      ),
    ];
  }
}
