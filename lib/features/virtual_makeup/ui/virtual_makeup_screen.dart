import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';
import 'package:flutter/material.dart';

import '../domain/face_quality.dart';
import '../domain/makeup_look.dart';
import '../landmarks/face_landmark_provider.dart';
import '../landmarks/mediapipe_landmark_provider.dart';
import 'disclaimer_banner.dart';
import 'makeup_controls.dart';
import 'mask_editor.dart';
import 'photo_io.dart';
import 'photo_view.dart';
import 'virtual_makeup_controller.dart';

enum _Tab { makeup, protection }

/// Virtual try-on of lipstick, eyeshadow and blush on the user's own photo.
/// Self-contained: it does not read the catalog, the database or the skin
/// analysis, and it does not change them.
class VirtualMakeupScreen extends StatefulWidget {
  const VirtualMakeupScreen({super.key, this.landmarks, this.photos});

  /// Tests and future engines can replace the face finder and the photo source.
  final FaceLandmarkProvider? landmarks;
  final MakeupPhotoSource? photos;

  @override
  State<VirtualMakeupScreen> createState() => _VirtualMakeupScreenState();
}

class _VirtualMakeupScreenState extends State<VirtualMakeupScreen> {
  late final VirtualMakeupController _c;
  late final MakeupPhotoSource _photos;
  _Tab _tab = _Tab.makeup;
  bool _erase = false;
  double _brush = 0.022;
  bool _drawing = false;

  @override
  void initState() {
    super.initState();
    _photos = widget.photos ?? const ImagePickerMakeupPhotoSource();
    _c = VirtualMakeupController(
      landmarks: widget.landmarks ?? MediaPipeLandmarkProvider(),
    )..addListener(_onChange);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c
      ..removeListener(_onChange)
      ..dispose();
    super.dispose();
  }

  Future<void> _pick(bool camera) async {
    try {
      final bytes = await _photos.pick(camera: camera);
      if (bytes == null || !mounted) return;
      _tab = _Tab.makeup;
      await _c.loadPhoto(bytes);
    } catch (_) {
      if (mounted) {
        showMessage(
          context,
          tr('Не удалось открыть фото'),
          type: MessageType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: tr('Виртуальная примерка'),
      showNav: false,
      child: Column(
        children: [
          // pinned: the result is a preview, and this must never scroll away
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: DisclaimerBanner(),
          ),
          Expanded(
            child: ListView(
              physics: _drawing ? const NeverScrollableScrollPhysics() : null,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: _body(context),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _body(BuildContext context) {
    final pal = context.pal;
    switch (_c.status) {
      case MakeupStatus.empty:
        return [_picker(context)];
      case MakeupStatus.loading:
        return [
          const SizedBox(height: 60),
          Center(
            key: const Key('vm-loading'),
            child: Column(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text(tr('Ищем лицо…')),
              ],
            ),
          ),
        ];
      case MakeupStatus.noFace:
        return [
          _problem(
            'Лицо не найдено. Выберите фото, где лицо хорошо видно и смотрит в камеру.',
            const Key('vm-no-face'),
          ),
          _picker(context),
        ];
      case MakeupStatus.severalFaces:
        return [
          _problem(
            'На фото несколько лиц. Выберите фото с одним лицом: иначе примерка была бы догадкой.',
            const Key('vm-several-faces'),
          ),
          _picker(context),
        ];
      case MakeupStatus.failed:
        return [
          _problem(
            'Не удалось обработать фото. Попробуйте другое.',
            const Key('vm-failed'),
          ),
          _picker(context),
        ];
      case MakeupStatus.ready:
        final q = _c.quality!;
        return [
          MakeupPhotoView(
            controller: _c,
            editing: _tab == _Tab.protection,
            brushRadius: _brush,
            erase: _erase,
            onDrawing: (v) => setState(() => _drawing = v),
          ),
          const SizedBox(height: 10),
          SegmentedButton<CompareMode>(
            key: const Key('vm-compare'),
            // three short words in one row: no room for the tick
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: CompareMode.result,
                label: Text(tr('Результат')),
              ),
              ButtonSegment(
                value: CompareMode.original,
                label: Text(tr('Оригинал')),
              ),
              ButtonSegment(
                value: CompareMode.split,
                label: Text(tr('Разделитель')),
              ),
            ],
            selected: {_c.compare},
            onSelectionChanged: (v) => _c.setCompare(v.first),
          ),
          const SizedBox(height: 4),
          Text(
            tr('Удерживайте фото, чтобы увидеть оригинал.'),
            style: AppTextStyles.caption.copyWith(color: pal.subtext),
          ),
          for (final issue in q.issues) _issue(issue),
          const SizedBox(height: 10),
          SegmentedButton<_Tab>(
            key: const Key('vm-tabs'),
            segments: [
              ButtonSegment(
                value: _Tab.makeup,
                icon: const Icon(Icons.brush),
                label: Text(tr('Макияж')),
              ),
              ButtonSegment(
                value: _Tab.protection,
                icon: const Icon(Icons.shield_outlined),
                label: Text(tr('Защита кожи')),
              ),
            ],
            selected: {_tab},
            onSelectionChanged: (v) => setState(() => _tab = v.first),
          ),
          const SizedBox(height: 10),
          if (_tab == _Tab.makeup)
            for (final z in MakeupZone.values) ...[
              ZoneControl(
                zone: z,
                look: _c.look.of(z),
                onChanged: (v) => _c.setZone(z, v),
              ),
              const SizedBox(height: 8),
            ]
          else
            MaskEditorPanel(
              controller: _c,
              erase: _erase,
              brushRadius: _brush,
              onErase: (v) => setState(() => _erase = v),
              onBrushRadius: (v) => setState(() => _brush = v),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('vm-other-photo'),
            onPressed: () => _pick(false),
            icon: const Icon(Icons.photo_outlined),
            label: Text(tr('Другое фото')),
          ),
        ];
    }
  }

  Widget _issue(QualityIssue issue) {
    final text = switch (issue) {
      QualityIssue.turnedHead =>
        'Голова повёрнута: губы, веки и румяна могут лечь неточно.',
      QualityIssue.tiltedHead => 'Голова наклонена: зоны могут лечь неточно.',
      QualityIssue.smallFace =>
        'Лицо на фото маленькое: зоны состоят из малого числа точек, результат грубее.',
      QualityIssue.severalFaces => 'На фото несколько лиц.',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        key: Key('vm-issue-${issue.name}'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: AppColors.warning,
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(tr(text), style: AppTextStyles.small)),
        ],
      ),
    );
  }

  Widget _problem(String text, Key key) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: AppCard(
      key: key,
      child: Text(tr(text), style: AppTextStyles.body),
    ),
  );

  Widget _picker(BuildContext context) {
    final pal = context.pal;
    return AppCard(
      key: const Key('vm-picker'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Примерьте макияж на своё фото'), style: AppTextStyles.title),
          const SizedBox(height: 6),
          Text(
            tr(
              'Фото обрабатывается на телефоне: оно не отправляется на сервер и не сохраняется.',
            ),
            style: AppTextStyles.small.copyWith(color: pal.subtext),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('vm-gallery'),
              onPressed: () => _pick(false),
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(tr('Выбрать фото')),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('vm-camera'),
              onPressed: () => _pick(true),
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(tr('Сделать снимок')),
            ),
          ),
        ],
      ),
    );
  }
}
