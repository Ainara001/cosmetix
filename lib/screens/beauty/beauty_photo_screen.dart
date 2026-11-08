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
import 'package:cosmetix/services/ai/ai_config.dart';
import 'package:cosmetix/services/ai/ai_disclosure.dart';
import 'package:cosmetix/services/ai/vision_analyzer.dart';
import 'package:cosmetix/services/beauty_test_flow.dart';
import 'package:cosmetix/screens/beauty/photo_issue_text.dart';
import 'package:cosmetix/services/photo_check/photo_check.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/custom_button.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';

enum _Step { intro, preview, checking, rejected, warned, analyzing, failed }

/// Beauty Test, last step (OPTIONAL): a photo can improve the result. The
/// test always finishes without it.
class BeautyPhotoScreen extends StatefulWidget {
  const BeautyPhotoScreen({super.key, required this.args, this.picker});

  final BeautyPhotoArgs args;

  /// Where the photo comes from: the path of the picked file, or null when the
  /// user cancelled. Null = the phone's camera / gallery (image_picker); tests
  /// pass a fake.
  final Future<String?> Function(ImageSource source)? picker;

  @override
  State<BeautyPhotoScreen> createState() => _BeautyPhotoScreenState();
}

class _BeautyPhotoScreenState extends State<BeautyPhotoScreen> {
  _Step _step = _Step.intro;

  /// Too many skipped questions: the AI must determine the colour type.
  bool get _needsPhoto => widget.args.color.isWeak;
  File? _photo;
  String? _error;

  /// Why the local check refused (or warned about) the photo.
  List<PhotoIssue> _issues = const [];
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
      final String? path;
      if (widget.picker != null) {
        path = await widget.picker!(source);
      } else {
        final x = await ImagePicker().pickImage(
          source: source,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 80,
          preferredCameraDevice: CameraDevice.front,
        );
        path = x?.path;
      }
      if (path == null || !mounted) return;
      _discardPhoto();
      setState(() {
        _photo = File(path!);
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

  Future<bool> _photoAllowed(AiProvider ai) async {
    if (!AiConfig.photoAnalysisAtBuild) return false;
    if (ai.status != AiStatus.online) await ai.testConnection();
    return ai.photoAnalysisAllowed;
  }

  Future<void> _analyze() async {
    final photo = _photo;
    if (photo == null) return;
    final ai = context.read<AiProvider>();
    if (!ai.ageAllowed) {
      // the Gemini API terms: no remote AI for under-18s or an unknown age;
      // the photo is deleted, nothing is sent
      _discardPhoto();
      setState(() {
        _error = tr('Анализ по фото доступен с 18 лет.');
        _step = _Step.failed;
      });
      return;
    }
    // 1. the local check: on the phone, before ANY call to a server. A photo that
    //    does not pass it is deleted here and nothing is sent or changed.
    setState(() => _step = _Step.checking);
    PhotoCheckResult checked;
    try {
      checked = await context.read<PhotoCheck>().run(await photo.readAsBytes());
    } catch (_) {
      checked = PhotoCheckResult(
        const PhotoVerdict.reject(PhotoIssue.unreadable),
      );
    }
    if (!mounted) return;
    if (!checked.verdict.accepted) {
      _discardPhoto();
      setState(() {
        _issues = checked.verdict.issues;
        _step = _Step.rejected;
      });
      return;
    }
    if (checked.verdict.level == PhotoLevel.warn) {
      // usable, but not good: the user decides, with the reasons in front of them
      setState(() {
        _issues = checked.verdict.issues;
        _step = _Step.warned;
      });
      return;
    }
    await _send(photo, ai);
  }

  /// The photo passed the local check: only now may it go further (server
  /// switch, consent, the AI).
  Future<void> _send(File photo, AiProvider ai) async {
    // the photo leaves the phone only if the server said, explicitly, that it
    // accepts photos; otherwise it is deleted here and nothing is sent
    final allowed = await _photoAllowed(ai);
    if (!mounted) return;
    if (!allowed) {
      final off = ai.status == AiStatus.online;
      _discardPhoto();
      setState(() {
        _error = off
            ? tr('Анализ по фото сейчас отключён.')
            : tr('ИИ-сервер недоступен.');
        _step = _Step.failed;
      });
      return;
    }
    if (!ai.sharePhotos) {
      // privacy: the photo goes to the AI only with the user's agreement
      final ok = await confirmDialog(
        context,
        title: tr('Отправить фото в ИИ?'),
        message: AiDisclosure.photoConsent(ai.dataUse, ai.mode, tr),
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
      if (e is AiPhotoDisabled) ai.markPhotoDisabled();
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
    AiNotAllowed() => tr('Анализ по фото доступен с 18 лет.'),
    AiPhotoDisabled() => tr('Анализ по фото сейчас отключён.'),
    AiServerError() => tr('ИИ вернул ошибку. Попробуйте ещё раз позже.'),
    AiBadResponse() => tr('Не удалось разобрать ответ ИИ.'),
  };

  void _backToQuestions() {
    _discardPhoto();
    Navigator.of(
      context,
    ).popUntil((r) => r.isFirst || r.settings.name == AppRoutes.colorTest);
  }

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
    if (p.colorType == null) {
      // skipped questions and no usable photo: there is nothing to save
      _saving = false;
      if (!mounted) return;
      setState(() {
        _error = tr('ИИ не смог уверенно определить цветотип по этому фото.');
        _step = _Step.failed;
      });
      return;
    }
    try {
      await context.read<AuthProvider>().updateBeauty(
        skinType: p.skinType!.label,
        skinTone: p.skinTone?.label,
        undertone: p.undertone?.label,
        colorType: p.colorType?.label,
        skinConcerns: [for (final c in p.concerns) c.label],
        source: p.source.code,
        // the model's self-reported number is not a measurement: not stored
        clearConfidence: true,
        markCompleted: true,
      );
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        AppRoutes.colorResult,
        arguments: BeautyResultArgs(profile: p, photoUsed: merged.photoUsed),
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
      title: _needsPhoto ? tr('Фото для ИИ') : tr('Фото (по желанию)'),
      child: switch (_step) {
        _Step.intro => _intro(context),
        _Step.preview => _preview(context),
        _Step.checking => _checking(context),
        _Step.rejected => _rejected(context),
        _Step.warned => _warned(context),
        _Step.analyzing => _analyzing(context),
        _Step.failed => _failed(context),
      },
    );
  }

  Widget _intro(BuildContext context) {
    final pal = context.pal;
    final ai = context.watch<AiProvider>();
    if (!ai.ageAllowed) return _ageBlocked(context, ai);
    final tips = [
      tr('Естественное или нейтральное освещение'),
      tr('Лицо хорошо видно, без фильтров'),
      tr('Желательно без яркого макияжа'),
      tr('Смотрите прямо в камеру'),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Text(
          _needsPhoto
              ? tr('ИИ определит цветотип по фото')
              : tr('Улучшите результат с помощью фото'),
          style: AppTextStyles.h2,
        ),
        const SizedBox(height: 6),
        Text(
          _needsPhoto
              ? tr(
                  'Вы пропустили много вопросов, поэтому ИИ посмотрит на фото и сам определит цветотип, подтон и тон кожи.',
                )
              : tr(
                  'Фото — необязательный шаг. ИИ использует его только как дополнительную подсказку; ваши ответы важнее.',
                ),
          style: AppTextStyles.body.copyWith(color: pal.subtext),
        ),
        const SizedBox(height: 14),
        AppCard(
          color: context.pal.pinkSoft,
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
                      Icon(
                        Icons.check_circle_outline,
                        size: 16,
                        color: context.pal.accent,
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
        AppCard(
          color: context.pal.pinkSoft,
          borderColor: Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('Что стоит знать об анализе по фото'),
                style: AppTextStyles.subtitle,
              ),
              const SizedBox(height: 8),
              for (final t in [
                tr('Это подсказка по цвету, а не измерение и не диагноз.'),
                tr(
                  'Результат зависит от света и камеры; макияж, очки и фильтры его искажают.',
                ),
                tr('Приложение не определяет акне, рубцы или покраснения.'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: context.pal.accent,
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
                  'Фото уходит на сервер ИИ только после вашего согласия. Cosmetix его не сохраняет.',
                ),
                style: AppTextStyles.caption.copyWith(color: pal.subtext),
              ),
            ),
          ],
        ),
        if (ai.photoAnalysisOff) ...[
          const SizedBox(height: 10),
          Text(
            tr(
              'Анализ по фото сейчас отключён. Тест работает по вашим ответам, фото не нужно.',
            ),
            style: AppTextStyles.caption.copyWith(color: AppColors.sale),
          ),
        ] else if (!ai.isConfigured || ai.status == AiStatus.offline) ...[
          const SizedBox(height: 10),
          Text(
            tr(
              'ИИ-сервер сейчас недоступен — анализ фото не сработает, но тест можно завершить и без него.',
            ),
            style: AppTextStyles.caption.copyWith(color: AppColors.sale),
          ),
        ],
        const SizedBox(height: 20),
        if (!ai.photoAnalysisOff) ...[
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
        ],
        if (_needsPhoto)
          TextButton(
            onPressed: _backToQuestions,
            child: Text(tr('Вернуться к вопросам')),
          )
        else
          TextButton(onPressed: _skip, child: Text(tr('Пропустить'))),
      ],
    );
  }

  /// Under 18 or age not given: the photo step is not offered at all.
  Widget _ageBlocked(BuildContext context, AiProvider ai) {
    final pal = context.pal;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      children: [
        Icon(Icons.lock_outline, size: 48, color: pal.accent),
        const SizedBox(height: 12),
        Text(
          tr('Анализ по фото доступен с 18 лет'),
          textAlign: TextAlign.center,
          style: AppTextStyles.title,
        ),
        const SizedBox(height: 6),
        Text(
          ai.ageUnknown
              ? tr(
                  'Укажите год рождения в профиле. Тест работает и без фото, по вашим ответам.',
                )
              : tr('Тест работает и без фото, по вашим ответам.'),
          textAlign: TextAlign.center,
          style: AppTextStyles.small.copyWith(color: pal.subtext),
        ),
        const SizedBox(height: 20),
        if (_needsPhoto)
          CustomButton(
            label: tr('Вернуться к вопросам'),
            onPressed: _backToQuestions,
          )
        else
          CustomButton(label: tr('Продолжить без фото'), onPressed: _skip),
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
        if (!_needsPhoto)
          TextButton(onPressed: _skip, child: Text(tr('Пропустить'))),
      ],
    );
  }

  Widget _checking(BuildContext context) {
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
              tr('Проверяем фото…'),
              style: AppTextStyles.title,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              tr('Проверка идёт на телефоне, фото никуда не отправляется.'),
              style: AppTextStyles.small.copyWith(color: pal.subtext),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// The photo was refused: why, and the way to another photo.
  Widget _rejected(BuildContext context) {
    final pal = context.pal;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      children: [
        Icon(Icons.photo_camera_back_outlined, size: 48, color: pal.accent),
        const SizedBox(height: 12),
        Text(
          tr('Это фото не подходит'),
          textAlign: TextAlign.center,
          style: AppTextStyles.title,
        ),
        const SizedBox(height: 10),
        for (final i in _issues)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              photoIssueText(i),
              textAlign: TextAlign.center,
              style: AppTextStyles.body,
            ),
          ),
        const SizedBox(height: 6),
        Text(
          tr('Фото не отправлено и удалено с телефона.'),
          textAlign: TextAlign.center,
          style: AppTextStyles.small.copyWith(color: pal.subtext),
        ),
        const SizedBox(height: 20),
        CustomButton(
          label: tr('Выбрать другое фото'),
          onPressed: () => setState(() => _step = _Step.intro),
        ),
        const SizedBox(height: 10),
        if (_needsPhoto)
          CustomButton(
            label: tr('Вернуться к вопросам'),
            outlined: true,
            onPressed: _backToQuestions,
          )
        else
          CustomButton(
            label: tr('Продолжить без фото'),
            outlined: true,
            onPressed: _skip,
          ),
      ],
    );
  }

  /// The photo is usable but not good: the user decides.
  Widget _warned(BuildContext context) {
    final pal = context.pal;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      children: [
        Icon(Icons.info_outline, size: 48, color: pal.accent),
        const SizedBox(height: 12),
        Text(
          tr('Фото можно использовать, но результат может быть неточным'),
          textAlign: TextAlign.center,
          style: AppTextStyles.title,
        ),
        const SizedBox(height: 10),
        for (final i in _issues)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              photoIssueText(i),
              textAlign: TextAlign.center,
              style: AppTextStyles.body,
            ),
          ),
        const SizedBox(height: 20),
        CustomButton(
          label: tr('Использовать это фото'),
          onPressed: () {
            final photo = _photo;
            if (photo != null) _send(photo, context.read<AiProvider>());
          },
        ),
        const SizedBox(height: 10),
        CustomButton(
          label: tr('Выбрать другое фото'),
          outlined: true,
          onPressed: () {
            _discardPhoto();
            setState(() => _step = _Step.intro);
          },
        ),
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
        Icon(Icons.cloud_off_outlined, size: 48, color: context.pal.accent),
        const SizedBox(height: 12),
        Text(
          _error ?? tr('Не удалось проанализировать фото.'),
          textAlign: TextAlign.center,
          style: AppTextStyles.title,
        ),
        const SizedBox(height: 6),
        Text(
          _needsPhoto
              ? tr(
                  'Попробуйте другое фото при дневном свете или ответьте на вопросы теста.',
                )
              : tr(
                  'Ничего страшного: результат можно получить по ответам теста.',
                ),
          textAlign: TextAlign.center,
          style: AppTextStyles.small.copyWith(color: pal.subtext),
        ),
        const SizedBox(height: 20),
        if (!_needsPhoto) ...[
          CustomButton(
            label: tr('Продолжить без фото'),
            onPressed: () => _finish(null),
          ),
          const SizedBox(height: 10),
        ],
        CustomButton(
          label: tr('Попробовать другое фото'),
          outlined: !_needsPhoto,
          onPressed: () => setState(() => _step = _Step.intro),
        ),
        if (_needsPhoto) ...[
          const SizedBox(height: 10),
          CustomButton(
            label: tr('Вернуться к вопросам'),
            outlined: true,
            onPressed: _backToQuestions,
          ),
        ],
      ],
    );
  }
}
