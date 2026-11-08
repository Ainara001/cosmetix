import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:cosmetix/core/face/face_coordinate_transform.dart';
import 'package:cosmetix/core/face/face_geometry.dart';
import 'package:cosmetix/core/face/face_points.dart';
import 'package:cosmetix/core/face/face_zones.dart';
import 'package:cosmetix/core/face/mean_mesh.dart';
import 'package:cosmetix/core/face/mediapipe_face_engine.dart';
import 'package:cosmetix/core/i18n/tr.dart';
import 'package:cosmetix/core/theme/app_colors.dart';
import 'package:cosmetix/core/theme/app_text_styles.dart';
import 'package:cosmetix/core/utils/ui_helpers.dart';
import 'package:cosmetix/models/skin_marks.dart';
import 'package:cosmetix/providers/auth_provider.dart';
import 'package:cosmetix/repositories/skin_marks_repository.dart';
import 'package:cosmetix/services/photo_check/photo_pixels.dart';
import 'package:cosmetix/widgets/app_card.dart';
import 'package:cosmetix/widgets/common_widgets.dart';
import 'package:cosmetix/widgets/custom_button.dart';
import 'package:cosmetix/widgets/page_scaffold.dart';

/// A face of the person's own photo: the picture and its mesh.
typedef PhotoFace = ({ui.Image image, FaceGeometry face});

/// Finds the one face of a photo, on the phone; null when there is not
/// exactly one. Tests pass a fake.
typedef PhotoFaceLocator = Future<PhotoFace?> Function(Uint8List bytes);

/// The person marks what they see on each zone of their face: on a schematic
/// face, or over their own photo (kept in memory only, never saved or sent).
/// The marks are observations, not a diagnosis; they are saved on the phone
/// and used by the care selection.
class SkinMarksScreen extends StatefulWidget {
  const SkinMarksScreen({super.key, this.locate, this.pickPhoto});

  final PhotoFaceLocator? locate;

  /// The photo bytes, or null when cancelled. Null = the gallery.
  final Future<Uint8List?> Function()? pickPhoto;

  @override
  State<SkinMarksScreen> createState() => _SkinMarksScreenState();
}

/// The default locator: MediaPipe on the phone, one face only.
Future<PhotoFace?> locateOnPhone(Uint8List bytes) async {
  final px = await PhotoPixels.decode(bytes, maxSide: 1280);
  final engine = MediaPipeFaceEngine(maxFaces: 2);
  try {
    final faces = await engine.detect(px.rgba, px.width, px.height);
    if (faces.length != 1) return null;
    final buffer = await ui.ImmutableBuffer.fromUint8List(px.rgba);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: px.width,
      height: px.height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return (image: image, face: faces.first);
  } finally {
    await engine.dispose();
  }
}

class _SkinMarksScreenState extends State<SkinMarksScreen> {
  static const _schematicSize = Size(300, 390);
  static final _schematic = FaceGeometry(
    FacePoints(meanFace(const Offset(150, 185), 250)),
    imageSize: _schematicSize,
  );

  Set<SkinZoneMark> _marks = {};
  FaceZone _zone = FaceZone.forehead;
  PhotoFace? _photo;
  bool _loading = true;
  bool _busy = false;

  FaceGeometry get _face => _photo?.face ?? _schematic;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    final repo = context.read<SkinMarksRepository>();
    final current = auth.user == null
        ? SkinMarks.empty
        : await repo.current(auth.userId);
    if (!mounted) return;
    setState(() {
      _marks = {...current.marks};
      _loading = false;
    });
  }

  @override
  void dispose() {
    _photo?.image.dispose(); // the photo lived in memory only
    super.dispose();
  }

  void _toggle(SkinFeature f) => setState(() {
    final m = SkinZoneMark(_zone, f);
    if (!_marks.remove(m)) _marks.add(m);
  });

  Future<void> _usePhoto() async {
    setState(() => _busy = true);
    try {
      final bytes = widget.pickPhoto != null
          ? await widget.pickPhoto!()
          : await (await ImagePicker().pickImage(
              source: ImageSource.gallery,
              maxWidth: 1280,
              maxHeight: 1280,
            ))?.readAsBytes();
      if (bytes == null || !mounted) return;
      final found = await (widget.locate ?? locateOnPhone)(bytes);
      if (!mounted) return;
      if (found == null) {
        showMessage(
          context,
          tr(
            'На фото нужно одно лицо, крупно и анфас. Можно отмечать на схеме.',
          ),
          type: MessageType.warning,
        );
        return;
      }
      _photo?.image.dispose();
      setState(() => _photo = found);
    } catch (_) {
      if (mounted) {
        showMessage(
          context,
          tr('Не удалось открыть фото. Можно отмечать на схеме.'),
          type: MessageType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;
    setState(() => _busy = true);
    await context.read<SkinMarksRepository>().replace(auth.userId, _marks);
    if (!mounted) return;
    setState(() => _busy = false);
    showMessage(context, tr('Отметки сохранены'), type: MessageType.success);
    Navigator.of(context).maybePop(true);
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final summary = SkinMarks(_marks);
    return PageScaffold(
      title: tr('Особенности кожи'),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                Text(
                  tr('Выберите зону и отметьте, что вы на ней видите.'),
                  style: AppTextStyles.body,
                ),
                const SizedBox(height: 12),
                _FaceView(
                  face: _face,
                  image: _photo?.image,
                  selected: _zone,
                  marked: {for (final m in _marks) m.zone},
                  onZone: (z) => setState(() => _zone = z),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.center,
                  child: _photo == null
                      ? TextButton.icon(
                          onPressed: _busy ? null : _usePhoto,
                          icon: const Icon(Icons.photo_outlined),
                          label: Text(tr('Отметить на своём фото')),
                        )
                      : TextButton.icon(
                          onPressed: () => setState(() {
                            _photo?.image.dispose();
                            _photo = null;
                          }),
                          icon: const Icon(Icons.face_outlined),
                          label: Text(tr('Вернуться к схеме')),
                        ),
                ),
                if (_photo != null)
                  Text(
                    tr(
                      'Фото только на экране: оно не сохраняется и никуда не отправляется.',
                    ),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.caption.copyWith(color: pal.subtext),
                  ),
                const SizedBox(height: 8),
                // the zones as buttons too: easy to reach with VoiceOver and
                // with large text, not only by tapping the picture
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final z in FaceZone.values)
                      AppChip(
                        label: summary.on(z).isEmpty
                            ? tr(z.label)
                            : '${tr(z.label)} · ${summary.on(z).length}',
                        selected: z == _zone,
                        onTap: () => setState(() => _zone = z),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr(_zone.label), style: AppTextStyles.subtitle),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final f in SkinFeature.values)
                            FilterChip(
                              key: Key('feature-${f.code}'),
                              label: Text(tr(f.label)),
                              selected: _marks.contains(SkinZoneMark(_zone, f)),
                              onSelected: (_) => _toggle(f),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (summary.concerns.isNotEmpty)
                  Text(
                    trf('В подборе ухода учтём: {v}', {
                      'v': summary.concerns.map((c) => tr(c.label)).join(', '),
                    }),
                    style: AppTextStyles.small,
                  ),
                if (summary.suggestsDermatologist)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      tr(
                        'Рубцы косметика не убирает: с ними лучше обратиться к дерматологу.',
                      ),
                      style: AppTextStyles.small.copyWith(color: pal.accent),
                    ),
                  ),
                const SizedBox(height: 12),
                CustomButton(
                  label: tr('Сохранить отметки'),
                  onPressed: _busy ? null : _save,
                ),
                const SizedBox(height: 12),
                Text(
                  tr(
                    'Это ваши наблюдения, а не диагноз: приложение не определяет акне, рубцы или пигментацию по фото. Если высыпаний много, они болезненные или оставляют следы, обратитесь к дерматологу.',
                  ),
                  style: AppTextStyles.caption.copyWith(color: pal.subtext),
                ),
              ],
            ),
    );
  }
}

/// The face (schematic or photo) with its zones; a tap selects a zone.
class _FaceView extends StatelessWidget {
  const _FaceView({
    required this.face,
    required this.image,
    required this.selected,
    required this.marked,
    required this.onZone,
  });

  final FaceGeometry face;
  final ui.Image? image;
  final FaceZone selected;
  final Set<FaceZone> marked;
  final ValueChanged<FaceZone> onZone;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return AspectRatio(
      aspectRatio: 300 / 390,
      child: LayoutBuilder(
        builder: (context, box) {
          final view = box.biggest;
          final t = FaceCoordinateTransform(
            imageSize: face.imageSize,
            previewSize: view,
            fit: FaceFit.contain,
          );
          final shown = face.mapped(t.toPreview, view);
          final zones = FaceZones.of(shown);
          return Semantics(
            label: tr('Схема лица: выберите зону кнопками ниже или касанием'),
            child: GestureDetector(
              key: const Key('face-view'),
              onTapUp: (d) {
                final z = zones.zoneAt(d.localPosition);
                if (z != null) onZone(z);
              },
              child: CustomPaint(
                size: view,
                painter: _ZonesPainter(
                  zones: zones,
                  image: image,
                  imageRect: Rect.fromPoints(
                    t.toPreview(Offset.zero),
                    t.toPreview(
                      Offset(face.imageSize.width, face.imageSize.height),
                    ),
                  ),
                  selected: selected,
                  marked: marked,
                  accent: pal.accent,
                  line: pal.subtext,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ZonesPainter extends CustomPainter {
  _ZonesPainter({
    required this.zones,
    required this.image,
    required this.imageRect,
    required this.selected,
    required this.marked,
    required this.accent,
    required this.line,
  });

  final FaceZones zones;
  final ui.Image? image;
  final Rect imageRect;
  final FaceZone selected;
  final Set<FaceZone> marked;
  final Color accent;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final img = image;
    final face = zones.face;
    if (img != null) {
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        imageRect,
        Paint(),
      );
    } else {
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = line;
      for (final part in [
        face.oval,
        face.eyeLeft,
        face.eyeRight,
        face.browLeft,
        face.browRight,
        face.lips,
      ]) {
        canvas.drawPath(Path()..addPolygon(part, true), stroke);
      }
    }
    for (final z in FaceZone.values) {
      final isSel = z == selected;
      final isMarked = marked.contains(z);
      final visible = zones.visible(z);
      canvas.drawPath(
        zones.path(z),
        Paint()
          ..color = accent.withValues(
            alpha: !visible ? 0.05 : (isSel ? 0.45 : (isMarked ? 0.28 : 0.12)),
          ),
      );
      canvas.drawPath(
        zones.path(z),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSel ? 2.5 : 1
          ..color = accent.withValues(alpha: isSel ? 1 : 0.6),
      );
    }
  }

  @override
  bool shouldRepaint(_ZonesPainter old) =>
      old.selected != selected ||
      old.marked.length != marked.length ||
      !old.marked.containsAll(marked) ||
      old.image != image ||
      old.zones.face != zones.face;
}
