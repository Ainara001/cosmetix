import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../domain/face_quality.dart';
import '../domain/makeup_look.dart';
import '../engine/blemish_suggester.dart';
import '../engine/color_transfer_backend.dart';
import '../engine/makeup_backend.dart';
import '../engine/protection_mask.dart';
import '../landmarks/face_landmark_provider.dart';
import '../engine/rgba_image.dart';
import 'photo_io.dart';

enum MakeupStatus { empty, loading, noFace, severalFaces, ready, failed }

enum CompareMode { result, original, split }

/// The state of the try-on screen. It holds ONE photo in memory (never saved,
/// never sent) and re-renders it when the look or the protection changes.
class VirtualMakeupController extends ChangeNotifier {
  VirtualMakeupController({
    required this.landmarks,
    this.backend = const ColorTransferBackend(),
    this.maxSide = 1280,
    this.debounce = const Duration(milliseconds: 60),
  });

  final FaceLandmarkProvider landmarks;
  final MakeupBackend backend;
  final int maxSide;
  final Duration debounce;

  MakeupStatus status = MakeupStatus.empty;
  PreparedFace? face;
  ui.Image? originalImage;
  ui.Image? resultImage;
  MakeupLook look = const MakeupLook();
  ProtectionMask? protection;
  BlemishSuggestion? suggestion;
  CompareMode compare = CompareMode.result;
  double split = 0.5;

  /// A small picture of the protected area and of the suggestion for drawing.
  ui.Image? protectionOverlay;
  ui.Image? suggestionOverlay;

  Timer? _timer;
  int _renderSeq = 0;
  bool _disposed = false;

  FaceQuality? get quality => face?.quality;
  bool get hasPhoto => face != null;

  /// Decodes a photo, finds the face and renders the first result.
  Future<void> loadPhoto(Uint8List bytes) async {
    _setStatus(MakeupStatus.loading);
    try {
      final rgba = await PhotoDecoder.decode(bytes, maxSide: maxSide);
      final faces = await landmarks.detect(rgba);
      _clear();
      if (faces.isEmpty) {
        _setStatus(MakeupStatus.noFace);
        return;
      }
      if (faces.length > 1) {
        _setStatus(MakeupStatus.severalFaces);
        return;
      }
      final prepared = PreparedFace.from(rgba, faces.first);
      originalImage = await PhotoDecoder.toUiImage(rgba);
      face = prepared;
      protection = ProtectionMask(rgba.width, rgba.height);
      look = const MakeupLook();
      compare = CompareMode.result;
      await _renderNow();
      _setStatus(MakeupStatus.ready);
    } catch (e) {
      debugPrint('virtual makeup: $e');
      _clear();
      _setStatus(MakeupStatus.failed);
    }
  }

  void _clear() {
    originalImage?.dispose();
    resultImage?.dispose();
    protectionOverlay?.dispose();
    suggestionOverlay?.dispose();
    originalImage = resultImage = protectionOverlay = suggestionOverlay = null;
    face = null;
    protection = null;
    suggestion = null;
  }

  void _setStatus(MakeupStatus s) {
    status = s;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ---------------------------------------------------------------- the look

  void setZone(MakeupZone zone, ZoneLook value) {
    look = look.with_(zone, value);
    _scheduleRender();
    _notify();
  }

  void setCompare(CompareMode mode) {
    compare = mode;
    _notify();
  }

  void setSplit(double value) {
    split = value.clamp(0.02, 0.98);
    _notify();
  }

  void _scheduleRender() {
    _timer?.cancel();
    if (debounce == Duration.zero) {
      unawaited(_renderNow());
    } else {
      _timer = Timer(debounce, () => unawaited(_renderNow()));
    }
  }

  Future<void> _renderNow() async {
    final f = face;
    if (f == null) return;
    final seq = ++_renderSeq;
    final out = await backend.render(
      MakeupRequest(face: f, look: look, protection: protection),
    );
    final img = await PhotoDecoder.toUiImage(out);
    if (_disposed || seq != _renderSeq) {
      img.dispose();
      return;
    }
    resultImage?.dispose();
    resultImage = img;
    _notify();
  }

  // ------------------------------------------------------ protection (by hand)

  bool _stroking = false;
  ui.Offset? _last;

  /// [p] is in photo pixels.
  void strokeStart(ui.Offset p, double radius, {required bool erase}) {
    final m = protection;
    if (m == null) return;
    m.beginStroke();
    _stroking = true;
    _last = p;
    m.dab(p.dx, p.dy, radius, erase: erase);
    _maskChanged();
  }

  void strokeMove(ui.Offset p, double radius, {required bool erase}) {
    final m = protection;
    if (m == null || !_stroking) return;
    final last = _last ?? p;
    m.stroke(last.dx, last.dy, p.dx, p.dy, radius, erase: erase);
    _last = p;
    _maskChanged();
  }

  void strokeEnd() {
    _stroking = false;
    _last = null;
    _scheduleRender();
  }

  void undo() {
    protection?.undo();
    _maskChanged(renderNow: true);
  }

  void redo() {
    protection?.redo();
    _maskChanged(renderNow: true);
  }

  void clearProtection() {
    protection?.clear();
    _maskChanged(renderNow: true);
  }

  void _maskChanged({bool renderNow = false}) {
    unawaited(_refreshOverlays());
    if (renderNow) _scheduleRender();
    _notify();
  }

  // ------------------------------------------------------------- suggestion

  /// Looks for small spots and shows them as a hint; nothing is protected until
  /// the user accepts.
  void suggest() {
    final f = face;
    if (f == null) return;
    suggestion = BlemishSuggester.suggest(f.image, f.masks, f.points.faceWidth);
    unawaited(_refreshOverlays());
    _notify();
  }

  void acceptSuggestion() {
    final s = suggestion, m = protection;
    if (s == null || m == null || !s.reliable) return;
    m.merge(s.mask);
    suggestion = null;
    _maskChanged(renderNow: true);
  }

  void dismissSuggestion() {
    suggestion = null;
    unawaited(_refreshOverlays());
    _notify();
  }

  Future<void> _refreshOverlays() async {
    final f = face;
    if (f == null) return;
    final w = f.image.width, h = f.image.height;
    final p = protection, s = suggestion;
    final pi = p != null && !p.isEmpty
        ? await _overlay(p.data, w, h, const [34, 160, 220])
        : null;
    final si = s != null && s.reliable && s.regions > 0
        ? await _overlay(s.mask, w, h, const [250, 190, 40])
        : null;
    if (_disposed) {
      pi?.dispose();
      si?.dispose();
      return;
    }
    protectionOverlay?.dispose();
    suggestionOverlay?.dispose();
    protectionOverlay = pi;
    suggestionOverlay = si;
    _notify();
  }

  /// A coloured, half-transparent picture of a mask, at most 360 px across.
  static Future<ui.Image> _overlay(
    Uint8List mask,
    int w,
    int h,
    List<int> rgb,
  ) => PhotoDecoder.toUiImage(overlayPixels(mask, w, h, rgb));

  /// The pixels of that picture. The colour is PREMULTIPLIED by the alpha, as
  /// the engine draws it: where the mask is 0 every channel is 0 (clear), where
  /// it is 255 the colour is at 55 % opacity.
  @visibleForTesting
  static RgbaImage overlayPixels(Uint8List mask, int w, int h, List<int> rgb) {
    final step = (w > h ? w : h) > 360 ? ((w > h ? w : h) / 360).ceil() : 1;
    final ow = (w / step).ceil(), oh = (h / step).ceil();
    final px = Uint8List(ow * oh * 4);
    for (var y = 0; y < oh; y++) {
      for (var x = 0; x < ow; x++) {
        final v =
            mask[(y * step).clamp(0, h - 1) * w + (x * step).clamp(0, w - 1)];
        final a = (v * 0.55).round();
        final o = (y * ow + x) * 4;
        px[o] = (rgb[0] * a / 255).round();
        px[o + 1] = (rgb[1] * a / 255).round();
        px[o + 2] = (rgb[2] * a / 255).round();
        px[o + 3] = a;
      }
    }
    return RgbaImage(ow, oh, px);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    originalImage?.dispose();
    resultImage?.dispose();
    protectionOverlay?.dispose();
    suggestionOverlay?.dispose();
    unawaited(landmarks.dispose());
    super.dispose();
  }
}
