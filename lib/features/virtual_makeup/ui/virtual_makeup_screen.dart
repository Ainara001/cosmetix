import 'dart:async';

import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/custom_button.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';
import 'package:cosmetix/widgets/pill_segments.dart';
import 'package:flutter/material.dart';

import '../catalog/try_on_item.dart';
import '../domain/face_quality.dart';
import '../domain/makeup_look.dart';
import '../landmarks/face_landmark_provider.dart';
import '../landmarks/mediapipe_landmark_provider.dart';
import 'catalog_panel.dart';
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
  const VirtualMakeupScreen({
    super.key,
    this.landmarks,
    this.photos,
    this.catalog,
    this.productId,
    this.onOpenProduct,
  });

  /// Tests and future engines can replace the face finder and the photo source.
  final FaceLandmarkProvider? landmarks;
  final MakeupPhotoSource? photos;

  /// The products of the shop that can be tried on (null: only the colours
  /// the user picks by hand, as in the first stage).
  final TryOnCatalog? catalog;

  /// A catalog product to show right away (the "Try on" button of its page).
  final int? productId;

  /// How to open the page of a product (cart, favourites live there).
  final ValueChanged<int>? onOpenProduct;

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
    // a face finder made here is freed here; one passed in stays its owner's
    _c = VirtualMakeupController(
      landmarks: widget.landmarks ?? MediaPipeLandmarkProvider(),
      ownsLandmarks: widget.landmarks == null,
      catalog: widget.catalog,
    )..addListener(_onChange);
    final id = widget.productId;
    if (id != null) unawaited(_c.startWith(id));
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
        return [_picker(context), ..._catalogBlock()];
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
          _notice(MakeupNotice.noFace),
          _picker(context),
          ..._catalogBlock(),
        ];
      case MakeupStatus.severalFaces:
        return [
          _notice(MakeupNotice.severalFaces),
          _picker(context),
          ..._catalogBlock(),
        ];
      case MakeupStatus.failed:
        return [
          _notice(MakeupNotice.failed),
          _picker(context),
          ..._catalogBlock(),
        ];
      case MakeupStatus.ready:
        final q = _c.quality!;
        return [
          // the last photo was refused, the one before it is still here
          if (_c.notice != null) _notice(_c.notice!),
          MakeupPhotoView(
            controller: _c,
            editing: _tab == _Tab.protection,
            brushRadius: _brush,
            erase: _erase,
            onDrawing: (v) => setState(() => _drawing = v),
          ),
          const SizedBox(height: 10),
          PillSegments<CompareMode>(
            key: const Key('vm-compare'),
            segments: [
              PillSegment(value: CompareMode.result, label: tr('Результат')),
              PillSegment(value: CompareMode.original, label: tr('Оригинал')),
              PillSegment(value: CompareMode.split, label: tr('Разделитель')),
            ],
            selected: _c.compare,
            onChanged: _c.setCompare,
          ),
          const SizedBox(height: 4),
          Text(
            tr('Удерживайте фото, чтобы увидеть оригинал.'),
            style: AppTextStyles.caption.copyWith(color: pal.subtext),
          ),
          for (final issue in q.issues) _issue(issue),
          const SizedBox(height: 10),
          PillSegments<_Tab>(
            key: const Key('vm-tabs'),
            segments: [
              PillSegment(
                value: _Tab.makeup,
                icon: Icons.brush,
                label: tr('Макияж'),
              ),
              PillSegment(
                value: _Tab.protection,
                icon: Icons.shield_outlined,
                label: tr('Защита кожи'),
              ),
            ],
            selected: _tab,
            onChanged: (v) => setState(() => _tab = v),
          ),
          const SizedBox(height: 10),
          if (_tab == _Tab.makeup)
            if (widget.catalog != null)
              ..._catalogBlock(withZoneControls: true)
            else
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
          CustomButton(
            key: const Key('vm-other-photo'),
            onPressed: () => _pick(false),
            icon: Icons.photo_outlined,
            label: tr('Другое фото'),
            outlined: true,
          ),
        ];
    }
  }

  /// The choice between products of the catalog and own colours, and what
  /// goes with the chosen mode. Empty when the screen has no catalog.
  List<Widget> _catalogBlock({bool withZoneControls = false}) {
    if (widget.catalog == null) return const [];
    return [
      const SizedBox(height: 10),
      ColourModeBar(controller: _c),
      const SizedBox(height: 10),
      if (_c.colourMode == ColourMode.catalog)
        CatalogPanel(controller: _c, onOpenProduct: widget.onOpenProduct)
      else if (withZoneControls)
        for (final z in MakeupZone.values) ...[
          ZoneControl(
            zone: z,
            look: _c.look.of(z),
            onChanged: (v) => _c.setZone(z, v),
          ),
          const SizedBox(height: 8),
        ],
    ];
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

  Widget _notice(MakeupNotice n) => switch (n) {
    MakeupNotice.noFace => _problem(
      'Лицо не найдено. Выберите фото, где лицо хорошо видно и смотрит в камеру.',
      const Key('vm-no-face'),
    ),
    MakeupNotice.severalFaces => _problem(
      'На фото несколько лиц. Выберите фото с одним лицом: иначе примерка была бы догадкой.',
      const Key('vm-several-faces'),
    ),
    MakeupNotice.failed => _problem(
      'Не удалось обработать фото. Попробуйте другое.',
      const Key('vm-failed'),
    ),
  };

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
          CustomButton(
            key: const Key('vm-gallery'),
            onPressed: () => _pick(false),
            icon: Icons.photo_library_outlined,
            label: tr('Выбрать фото'),
          ),
          const SizedBox(height: 8),
          CustomButton(
            key: const Key('vm-camera'),
            onPressed: () => _pick(true),
            icon: Icons.photo_camera_outlined,
            label: tr('Сделать снимок'),
            outlined: true,
          ),
        ],
      ),
    );
  }
}
