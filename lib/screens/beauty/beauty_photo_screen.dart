import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/models/ai_models.dart';
import 'package:cosmetix/providers/ai_provider.dart';
import 'package:cosmetix/providers/auth_provider.dart';
import 'package:cosmetix/routes/app_routes.dart';
import 'package:cosmetix/routes/route_args.dart';
import 'package:cosmetix/services/ai/ai_client.dart';
import 'package:cosmetix/services/ai/vision_analyzer.dart';
import 'package:cosmetix/services/beauty_test_flow.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/custom_button.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';

enum _Step { intro, preview, analyzing, failed }

/// Beauty Test, last step (OPTIONAL): a photo can improve the result. The
/// test always finishes without it.
class BeautyPhotoScreen extends StatefulWidget {
  const BeautyPhotoScreen({super.key, required this.args});

  final BeautyPhotoArgs args;

  @override
  State<BeautyPhotoScreen> createState() => _BeautyPhotoScreenState();
}

class _BeautyPhotoScreenState extends State<BeautyPhotoScreen> {
  _Step _step = _Step.intro;
  File? _photo;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // show whether the AI server is reachable (never blocks the screen)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ai = context.read<AiProvider>();
      if (ai.status == AiStatus.unknown) ai.testConnection();
    });
  }

  @override
  void dispose() {
    _discardPhoto();
    super.dispose();
  }

  /// The beauty photo is temporary: remove it when it is no longer needed.
  void _discardPhoto() {
    final f = _photo;
    _photo = null;
    if (f != null) {
      f.exists().then((e) {
        if (e) f.delete();
      });
    }
  }

  Future<void> _pick(ImageSource source) async {
    try {
      // the picker downsizes: we never send a 10-20 MB original
      final x = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
        preferredCameraDevice: CameraDevice.front,
      );
      if (x == null || !mounted) return;
      _discardPhoto();
      setState(() {
        _photo = File(x.path);
        _step = _Step.preview;
      });
    } catch (_) {
      if (mounted) {
        showMessage(
          context,
          tr('Не удалось получить фото. Проверьте доступ к камере/галерее.'),
          type: MessageType.error,
        );
      }
    }
  }

  Future<void> _analyze() async {
    final photo = _photo;
    if (photo == null) return;
    final ai = context.read<AiProvider>();
    if (!ai.sharePhotos) {
      // privacy: the photo goes to the AI only with the user's agreement
      final ok = await confirmDialog(
        context,
        title: tr('Отправить фото в ИИ?'),
        message: tr(
          'Фото будет отправлено на сервер ИИ только для анализа цветотипа и сразу удалено с телефона. Согласие можно отозвать в Настройках.',
        ),
        confirmLabel: tr('Разрешить'),
      );
      if (!ok || !mounted) return;
      await ai.setSharePhotos(true);
      if (!mounted) return;
    }
    setState(() => _step = _Step.analyzing);
    final analyzer = context.read<VisionAnalyzer>();
    try {
      final vision = await analyzer.analyzeFile(photo);
      _photo = null; // deleted by the analyzer
      ai.testConnection();
      await _finish(vision);
    } on AiException catch (e) {
      if (e is AiUnavailable || e is AiTimeout) ai.markOffline(e.message);
      if (!mounted) return;
      setState(() {
        _error = _friendly(e);
        _photo = null;
        _step = _Step.failed;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = tr('Не удалось проанализировать фото.');
        _photo = null;
        _step = _Step.failed;
      });
    }
  }

  String _friendly(AiException e) => switch (e) {
    AiUnavailable() => tr('ИИ-сервер недоступен.'),
    AiTimeout() => tr('ИИ отвечает слишком долго.'),
    AiRateLimited() => tr(
      'ИИ перегружен или лимит исчерпан. Попробуйте позже.',
    ),
    AiServerError() => tr('ИИ вернул ошибку. Попробуйте ещё раз позже.'),
    AiBadResponse() => tr('Не удалось разобрать ответ ИИ.'),
  };

  Future<void> _skip() async {
    _discardPhoto();
    await _finish(null);
  }

  Future<void> _finish(VisionAnalysis? vision) async {
    if (_saving) return;
    _saving = true;
    final a = widget.args;
    final merged = BeautyTestFlow.build(
      color: a.color,
      skinType: a.skinType,
      concerns: a.concerns,
      vision: vision,
    );
    final p = merged.profile;
    try {
      await context.read<AuthProvider>().updateBeauty(
        skinType: p.skinType!.label,
        skinTone: p.skinTone?.label,
        undertone: p.undertone?.label,
        colorType: p.colorType?.label,
        skinConcerns: [for (final c in p.concerns) c.label],
        source: p.source.code,
        confidence: merged.photoUsed ? p.confidence : null,
        clearConfidence: !merged.photoUsed,
        markCompleted: true,
      );
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        AppRoutes.colorResult,
        arguments: BeautyResultArgs(
          profile: p,
          photoUsed: merged.photoUsed,
          observations: merged.vision?.observations ?? const [],
        ),
      );
    } catch (_) {
      _saving = false;
      if (mounted) {
        showMessage(
          context,
          tr('Не удалось сохранить результат'),
          type: MessageType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: tr('Фото (по желанию)'),
      child: switch (_step) {
        _Step.intro => _intro(context),
        _Step.preview => _preview(context),
        _Step.analyzing => _analyzing(context),
        _Step.failed => _failed(context),
      },
    );
  }

  Widget _intro(BuildContext context) {
    final pal = context.pal;
    final ai = context.watch<AiProvider>();
    final tips = [
      tr('Естественное или нейтральное освещение'),
      tr('Лицо хорошо видно, без фильтров'),
      tr('Желательно без яркого макияжа'),
      tr('Смотрите прямо в камеру'),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Text(tr('Улучшите результат с помощью фото'), style: AppTextStyles.h2),
        const SizedBox(height: 6),
        Text(
          tr(
            'Фото — необязательный шаг. ИИ использует его только как дополнительную подсказку; ваши ответы важнее.',
          ),
          style: AppTextStyles.body.copyWith(color: pal.subtext),
        ),
        const SizedBox(height: 14),
        AppCard(
          color: AppColors.primarySoft,
          borderColor: Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('Как сделать хорошее фото'),
                style: AppTextStyles.subtitle,
              ),
              const SizedBox(height: 8),
              for (final t in tips)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        size: 16,
                        color: AppColors.primaryDark,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(t, style: AppTextStyles.small)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.lock_outline, size: 16, color: pal.subtext),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                tr(
                  'Ваше фото используется только для улучшения анализа бьюти-профиля и не сохраняется.',
                ),
                style: AppTextStyles.caption.copyWith(color: pal.subtext),
              ),
            ),
          ],
        ),
        if (!ai.isConfigured || ai.status == AiStatus.offline) ...[
          const SizedBox(height: 10),
          Text(
            tr(
              'ИИ-сервер сейчас недоступен — анализ фото не сработает, но тест можно завершить и без него.',
            ),
            style: AppTextStyles.caption.copyWith(color: AppColors.sale),
          ),
        ],
        const SizedBox(height: 20),
        CustomButton(
          label: tr('Сделать фото'),
          icon: Icons.photo_camera_outlined,
          onPressed: () => _pick(ImageSource.camera),
        ),
        const SizedBox(height: 10),
        CustomButton(
          label: tr('Выбрать из галереи'),
          icon: Icons.photo_library_outlined,
          outlined: true,
          onPressed: () => _pick(ImageSource.gallery),
        ),
        const SizedBox(height: 6),
        TextButton(onPressed: _skip, child: Text(tr('Пропустить'))),
      ],
    );
  }

  Widget _preview(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: AspectRatio(
            aspectRatio: 1,
            child: _photo == null
                ? const SizedBox()
                : Image.file(_photo!, fit: BoxFit.cover, cacheWidth: 900),
          ),
        ),
        const SizedBox(height: 16),
        CustomButton(label: tr('Использовать фото'), onPressed: _analyze),
        const SizedBox(height: 10),
        CustomButton(
          label: tr('Переснять'),
          outlined: true,
          onPressed: () {
            _discardPhoto();
            setState(() => _step = _Step.intro);
          },
        ),
        const SizedBox(height: 6),
        TextButton(onPressed: _skip, child: Text(tr('Пропустить'))),
      ],
    );
  }

  Widget _analyzing(BuildContext context) {
    final pal = context.pal;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 18),
            Text(
              tr('Анализируем фото…'),
              style: AppTextStyles.title,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              tr('Это может занять до минуты.'),
              style: AppTextStyles.small.copyWith(color: pal.subtext),
            ),
          ],
        ),
      ),
    );
  }

  Widget _failed(BuildContext context) {
    final pal = context.pal;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      children: [
        const Icon(
          Icons.cloud_off_outlined,
          size: 48,
          color: AppColors.primaryDark,
        ),
        const SizedBox(height: 12),
        Text(
          _error ?? tr('Не удалось проанализировать фото.'),
          textAlign: TextAlign.center,
          style: AppTextStyles.title,
        ),
        const SizedBox(height: 6),
        Text(
          tr('Ничего страшного: результат можно получить по ответам теста.'),
          textAlign: TextAlign.center,
          style: AppTextStyles.small.copyWith(color: pal.subtext),
        ),
        const SizedBox(height: 20),
        CustomButton(
          label: tr('Продолжить без фото'),
          onPressed: () => _finish(null),
        ),
        const SizedBox(height: 10),
        CustomButton(
          label: tr('Попробовать другое фото'),
          outlined: true,
          onPressed: () => setState(() => _step = _Step.intro),
        ),
      ],
    );
  }
}
