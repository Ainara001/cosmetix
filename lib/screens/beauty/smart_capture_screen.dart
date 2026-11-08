import 'dart:async';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsService;
import 'package:flutter/services.dart';
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart'
    show FaceMeshImage, FaceMeshPixelFormat;

import 'package:cosmetix/core/face/capture_guidance.dart';
import 'package:cosmetix/core/face/face_coordinate_transform.dart';
import 'package:cosmetix/core/face/face_geometry.dart';
import 'package:cosmetix/core/face/face_points.dart';
import 'package:cosmetix/core/face/face_stream_engine.dart';
import 'package:cosmetix/core/i18n/tr.dart';

/// One analysed camera frame, in FRAME pixel coordinates.
class LiveFrame {
  const LiveFrame({
    required this.face,
    required this.frameSize,
    this.faceLuma,
    this.took = Duration.zero,
  });

  final FaceGeometry? face;
  final Size frameSize;
  final double? faceLuma;

  /// Time the face mesh took for this frame (debug overlay only).
  final Duration took;
}

enum CameraProblem { noCamera, denied, failed }

class CameraUnavailable implements Exception {
  const CameraUnavailable(this.problem);
  final CameraProblem problem;
}

/// The camera the smart capture screen talks to. The app uses
/// [DeviceCaptureCamera]; tests pass a fake that feeds made-up frames.
abstract interface class CaptureCamera {
  /// Starts the preview and calls [onFrame] for every analysed frame.
  /// Throws [CameraUnavailable].
  Future<void> start(void Function(LiveFrame frame) onFrame);

  /// Size of the upright preview picture (same as the analysed frames).
  Size get previewSize;

  /// True when the analysed frames are a mirror image of what is shown.
  bool get mirrored;

  Widget buildPreview();

  /// Takes the photo; returns the file path.
  Future<String> takePicture();

  Future<void> dispose();
}

/// The front camera of the iPhone with the live face mesh.
///
/// On iOS the camera plugin delivers upright BGRA frames, mirrored for the
/// front camera exactly like the preview, so frame and preview coordinates
/// match without a flip (to be confirmed on a physical iPhone: see
/// docs/smart-face-capture.md).
class DeviceCaptureCamera implements CaptureCamera {
  CameraController? _controller;
  FaceStreamEngine? _engine;
  bool _closed = false;

  static bool get supported => Platform.isIOS;

  @override
  bool get mirrored => false;

  @override
  Size get previewSize {
    final s = _controller?.value.previewSize; // reported landscape
    if (s == null) return const Size(720, 1280);
    return Size(s.shortestSide, s.longestSide);
  }

  @override
  Future<void> start(void Function(LiveFrame frame) onFrame) async {
    final List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } on CameraException {
      throw const CameraUnavailable(CameraProblem.failed);
    }
    if (cameras.isEmpty) throw const CameraUnavailable(CameraProblem.noCamera);
    final front = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    // 1280x720: enough for the mesh and for the photo (the gallery photo is
    // downsized to 1024 for the same reason: no 10-20 MB originals)
    final c = CameraController(
      front,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.bgra8888,
    );
    _controller = c;
    try {
      await c.initialize();
      await c.lockCaptureOrientation(DeviceOrientation.portraitUp);
    } on CameraException catch (e) {
      throw CameraUnavailable(
        e.code.startsWith('CameraAccess')
            ? CameraProblem.denied
            : CameraProblem.failed,
      );
    }
    final engine = await FaceStreamEngine.start();
    if (_closed) {
      await engine.close(); // the screen was closed while starting
      return;
    }
    _engine = engine;
    await c.startImageStream((image) => _onImage(image, onFrame));
  }

  void _onImage(CameraImage image, void Function(LiveFrame) onFrame) {
    final engine = _engine;
    if (engine == null || engine.busy || _closed || image.planes.isEmpty) {
      return; // drop the frame: the mesh is still busy with the last one
    }
    final plane = image.planes.first;
    final bytes = plane.bytes;
    final w = image.width, h = image.height;
    final watch = Stopwatch()..start();
    engine
        .process(
          FaceMeshImage(
            pixels: bytes,
            width: w,
            height: h,
            bytesPerRow: plane.bytesPerRow,
            pixelFormat: FaceMeshPixelFormat.bgra,
          ),
        )
        .then((face) {
          if (_closed) return;
          onFrame(
            LiveFrame(
              face: face,
              frameSize: Size(w.toDouble(), h.toDouble()),
              faceLuma: face == null
                  ? null
                  : FaceStreamEngine.faceLuma(
                      bytes,
                      plane.bytesPerRow,
                      w,
                      h,
                      face.bounds,
                    ),
              took: watch.elapsed,
            ),
          );
        }, onError: (Object _) {});
  }

  @override
  Widget buildPreview() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return const SizedBox.shrink();
    return c.buildPreview();
  }

  @override
  Future<String> takePicture() async {
    final c = _controller!;
    if (c.value.isStreamingImages) await c.stopImageStream();
    final file = await c.takePicture();
    return file.path;
  }

  @override
  Future<void> dispose() async {
    _closed = true;
    final c = _controller;
    _controller = null;
    try {
      if (c != null && c.value.isStreamingImages) await c.stopImageStream();
    } catch (_) {}
    await c?.dispose();
    await _engine?.close();
    _engine = null;
  }
}

enum _Outcome { photo, cancelled, gallery, unavailable }

typedef _Result = ({_Outcome outcome, String? path});

/// What the person chose on the smart camera.
sealed class SmartCaptureResult {
  const SmartCaptureResult();
}

class CapturedPhoto extends SmartCaptureResult {
  const CapturedPhoto(this.path);
  final String path;
}

/// The person wants a photo from the gallery instead.
class UseGallery extends SmartCaptureResult {
  const UseGallery();
}

/// There is no usable camera here (e.g. the simulator): use the system one.
class CameraNotAvailable extends SmartCaptureResult {
  const CameraNotAvailable();
}

/// The front camera with a face guide: an oval that turns green when the face
/// is well placed, optional Face Mesh points, and one hint at a time. The
/// shutter is always available: the hints help, they never block. Frames are
/// analysed on the phone and never sent anywhere; the photo is checked again
/// by the photo check after it is taken.
class SmartCaptureScreen extends StatefulWidget {
  const SmartCaptureScreen({super.key, required this.camera});

  final CaptureCamera camera;

  /// Opens the screen; null when the person closed it.
  static Future<SmartCaptureResult?> open(
    BuildContext context, {
    CaptureCamera? camera,
  }) async {
    final r = await Navigator.of(context).push<_Result>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            SmartCaptureScreen(camera: camera ?? DeviceCaptureCamera()),
      ),
    );
    return switch (r?.outcome) {
      _Outcome.photo => CapturedPhoto(r!.path!),
      _Outcome.gallery => const UseGallery(),
      _Outcome.unavailable => const CameraNotAvailable(),
      _Outcome.cancelled || null => null,
    };
  }

  @override
  State<SmartCaptureScreen> createState() => _SmartCaptureScreenState();
}

/// The text of each hint (also used by the tests).
String captureHintText(CaptureHint hint) => switch (hint) {
  CaptureHint.noFace => tr('Поместите лицо в овал'),
  CaptureHint.moveToCenter => tr('Расположите лицо по центру'),
  CaptureHint.moveCloser => tr('Поднесите телефон ближе'),
  CaptureHint.moveBack => tr('Немного отодвиньте телефон'),
  CaptureHint.lookStraight => tr('Посмотрите прямо в камеру'),
  CaptureHint.levelHead => tr('Держите голову ровно'),
  CaptureHint.addLight => tr('Добавьте освещения'),
  CaptureHint.holdStill => tr('Не двигайтесь'),
  CaptureHint.ready => tr('Можно сделать фото'),
};

class _Live {
  const _Live(this.face, this.hint);
  final FaceGeometry? face; // in preview coordinates
  final CaptureHint hint;
}

class _SmartCaptureScreenState extends State<SmartCaptureScreen> {
  final _guidance = CaptureGuidance();
  final _live = ValueNotifier(const _Live(null, CaptureHint.noFace));
  bool _started = false;
  bool _taking = false;
  bool _showMesh = false;
  CameraProblem? _problem;
  Size _layout = Size.zero;

  // debug overlay
  int _frames = 0;
  double _fps = 0;
  Duration _took = Duration.zero;
  DateTime _fpsSince = DateTime.now();

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _start();
  }

  Future<void> _start() async {
    try {
      await widget.camera.start(_onFrame);
      if (mounted) setState(() => _started = true);
    } on CameraUnavailable catch (e) {
      if (!mounted) return;
      if (e.problem == CameraProblem.noCamera) {
        Navigator.of(
          context,
        ).pop<_Result>((outcome: _Outcome.unavailable, path: null));
      } else {
        setState(() => _problem = e.problem);
      }
    } catch (_) {
      if (mounted) setState(() => _problem = CameraProblem.failed);
    }
  }

  void _onFrame(LiveFrame f) {
    if (!mounted || _layout.isEmpty) return;
    final t = FaceCoordinateTransform(
      imageSize: f.frameSize,
      previewSize: _layout,
      mirror: widget.camera.mirrored,
    );
    final face = f.face?.mapped(t.toPreview, _layout);
    final hint = _guidance.update(
      CaptureFrame(
        face: face,
        oval: CaptureThresholds.ovalFor(_layout),
        faceLuma: f.faceLuma,
      ),
    );
    final previous = _live.value.hint;
    _live.value = _Live(face, hint);
    if (hint != previous) {
      // the hint is a live region: VoiceOver reads it when it changes
      SemanticsService.sendAnnouncement(
        View.of(context),
        captureHintText(hint),
        Directionality.of(context),
      );
    }
    if (kDebugMode) {
      _frames++;
      _took = f.took;
      final s = DateTime.now().difference(_fpsSince).inMilliseconds;
      if (s >= 1000) {
        setState(() {
          _fps = _frames * 1000 / s;
          _frames = 0;
          _fpsSince = DateTime.now();
        });
      }
    }
  }

  Future<void> _shoot() async {
    if (_taking || !_started) return;
    setState(() => _taking = true);
    try {
      final path = await widget.camera.takePicture();
      if (mounted) {
        Navigator.of(
          context,
        ).pop<_Result>((outcome: _Outcome.photo, path: path));
      }
    } catch (_) {
      if (mounted) setState(() => _problem = CameraProblem.failed);
    } finally {
      if (mounted) setState(() => _taking = false);
    }
  }

  void _close(_Outcome o) =>
      Navigator.of(context).pop<_Result>((outcome: o, path: null));

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(const []);
    widget.camera.dispose();
    _live.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _problem != null ? _problemView() : _cameraView(),
    );
  }

  Widget _problemView() {
    final text = _problem == CameraProblem.denied
        ? tr(
            'Нет доступа к камере. Разрешите его в Настройках iPhone или выберите фото из галереи.',
          )
        : tr('Камера не запустилась. Выберите фото из галереи.');
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => _close(_Outcome.gallery),
              child: Text(tr('Выбрать из галереи')),
            ),
            TextButton(
              onPressed: () => _close(_Outcome.cancelled),
              child: Text(
                tr('Закрыть'),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cameraView() {
    final preview = widget.camera.previewSize;
    return Stack(
      fit: StackFit.expand,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            _layout = box.biggest;
            return ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_started)
                    FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: preview.width,
                        height: preview.height,
                        child: widget.camera.buildPreview(),
                      ),
                    ),
                  ValueListenableBuilder(
                    valueListenable: _live,
                    builder: (context, live, _) => CustomPaint(
                      painter: _GuidePainter(
                        oval: CaptureThresholds.ovalFor(_layout),
                        ready: live.hint == CaptureHint.ready,
                        face: _showMesh ? live.face : null,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        SafeArea(
          child: Column(
            children: [
              _topBar(),
              const Spacer(),
              _hintBox(),
              const SizedBox(height: 16),
              _bottomBar(),
              const SizedBox(height: 12),
            ],
          ),
        ),
        if (kDebugMode && _started)
          Positioned(
            left: 8,
            top: MediaQuery.paddingOf(context).top + 56,
            child: Text(
              '${_fps.toStringAsFixed(1)} fps · ${_took.inMilliseconds} ms',
              style: const TextStyle(color: Colors.yellow, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _topBar() => Row(
    children: [
      IconButton(
        tooltip: tr('Закрыть'),
        color: Colors.white,
        icon: const Icon(Icons.close),
        onPressed: () => _close(_Outcome.cancelled),
      ),
      const Spacer(),
      IconButton(
        tooltip: _showMesh
            ? tr('Скрыть точки лица')
            : tr('Показать точки лица'),
        color: Colors.white,
        isSelected: _showMesh,
        icon: const Icon(Icons.blur_on_outlined),
        selectedIcon: const Icon(Icons.blur_on),
        onPressed: () => setState(() => _showMesh = !_showMesh),
      ),
    ],
  );

  Widget _hintBox() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: ValueListenableBuilder(
      valueListenable: _live,
      builder: (context, live, _) => Semantics(
        liveRegion: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: live.hint == CaptureHint.ready
                ? const Color(0xE62E7D32)
                : const Color(0xB3000000),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              _started ? captureHintText(live.hint) : tr('Запускаем камеру…'),
              key: const Key('capture-hint'),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _bottomBar() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              tooltip: tr('Выбрать из галереи'),
              color: Colors.white,
              iconSize: 30,
              icon: const Icon(Icons.photo_library_outlined),
              onPressed: () => _close(_Outcome.gallery),
            ),
          ),
        ),
        Semantics(
          button: true,
          label: tr('Сделать фото'),
          child: GestureDetector(
            key: const Key('capture-shutter'),
            onTap: _shoot,
            child: ValueListenableBuilder(
              valueListenable: _live,
              builder: (context, live, _) => Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: live.hint == CaptureHint.ready
                        ? const Color(0xFF66BB6A)
                        : Colors.white,
                    width: 5,
                  ),
                ),
                padding: const EdgeInsets.all(5),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _taking ? Colors.white54 : Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
        const Expanded(child: SizedBox()),
      ],
    ),
  );
}

/// The oval guide (grey, green when ready), a dimmed outside, and optionally
/// the Face Mesh points.
class _GuidePainter extends CustomPainter {
  _GuidePainter({required this.oval, required this.ready, this.face});

  final Rect oval;
  final bool ready;
  final FaceGeometry? face;

  @override
  void paint(Canvas canvas, Size size) {
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(oval);
    canvas.drawPath(outside, Paint()..color = const Color(0x66000000));
    canvas.drawOval(
      oval,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ready ? 5 : 3
        ..color = ready ? const Color(0xFF66BB6A) : const Color(0xCCFFFFFF),
    );
    final f = face;
    if (f == null) return;
    final dot = Paint()..color = const Color(0xCC80DEEA);
    for (final p in f.points.points.take(FaceIndices.meshSize)) {
      canvas.drawCircle(p, 1.2, dot);
    }
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFFFFFFFF);
    for (final part in [f.oval, f.eyeLeft, f.eyeRight, f.lips]) {
      canvas.drawPath(Path()..addPolygon(part, true), line);
    }
  }

  @override
  bool shouldRepaint(_GuidePainter old) =>
      old.ready != ready || old.face != face || old.oval != oval;
}
