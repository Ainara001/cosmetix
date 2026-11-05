import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../catalog/try_on_item.dart';
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

/// Why the LAST photo was not taken while an earlier photo is still on screen.
enum MakeupNotice { noFace, severalFaces, failed }

enum CompareMode { result, original, split }

/// Where the colours come from: products of the catalog, or hand-picked.
enum ColourMode { catalog, manual }

/// The state of the try-on screen. It holds ONE photo in memory (never saved,
/// never sent) and re-renders it when the look or the protection changes.
class VirtualMakeupController extends ChangeNotifier {
  VirtualMakeupController({
    required this.landmarks,
    this.ownsLandmarks = true,
    this.catalog,
    this.backend = const ColorTransferBackend(),
    this.maxSide = 1280,
    this.debounce = const Duration(milliseconds: 60),
  });

  final FaceLandmarkProvider landmarks;

  /// Whether [dispose] also frees [landmarks]. False when the caller made the
  /// provider and keeps using it after this screen.
  final bool ownsLandmarks;

  /// Products the try-on can show (null: only the hand-picked colours).
  final TryOnCatalog? catalog;
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

  /// Set when a new photo was refused and the previous one stayed.
  MakeupNotice? notice;

  // ---------------------------------------------------------- catalog mode

  ColourMode colourMode = ColourMode.manual;

  /// The product shown in each zone in [ColourMode.catalog] (one per kind).
  final Map<MakeupZone, TryOnItem> items = {};

  /// The product the user touched last: its shades and similar products are
  /// offered below.
  TryOnItem? current;
  List<TryOnItem> lineShades = const [];
  List<TryOnItem> similar = const [];

  /// The kind whose products the list shows when nothing is selected yet.
  MakeupZone browseKind = MakeupZone.lips;
  List<TryOnItem> browseList = const [];
  MakeupLook _manualLook = const MakeupLook();
  int _neighboursSeq = 0;

  /// A small picture of the protected area and of the suggestion for drawing.
  ui.Image? protectionOverlay;
  ui.Image? suggestionOverlay;

  Timer? _timer;
  int _renderSeq = 0;
  int _loadSeq = 0;
  bool _disposed = false;

  FaceQuality? get quality => face?.quality;
  bool get hasPhoto => face != null;

  /// Decodes a photo, finds the face and renders the first result.
  ///
  /// A photo that cannot be used (no face, several faces, broken file) does not
  /// throw away the photo already on screen: that one stays and [notice] says
  /// why the new one was refused. If a newer call starts meanwhile, this one
  /// gives up without touching anything.
  Future<void> loadPhoto(Uint8List bytes) async {
    final seq = ++_loadSeq;
    final hadPhoto = face != null;
    notice = null;
    _setStatus(MakeupStatus.loading);
    ui.Image? original, result;
    var adopted = false;
    try {
      final rgba = await PhotoDecoder.decode(bytes, maxSide: maxSide);
      final faces = await landmarks.detect(rgba);
      if (_superseded(seq)) return;
      if (faces.length != 1) {
        _refuse(
          hadPhoto,
          faces.isEmpty ? MakeupStatus.noFace : MakeupStatus.severalFaces,
        );
        return;
      }
      final prepared = PreparedFace.from(rgba, faces.first);
      final fresh = ProtectionMask(rgba.width, rgba.height);
      original = await PhotoDecoder.toUiImage(rgba);
      // a product chosen before the photo stays on it (catalog mode)
      final firstLook = colourMode == ColourMode.catalog
          ? look
          : const MakeupLook();
      result = await _draw(prepared, firstLook, fresh);
      if (_superseded(seq)) return;
      // nothing below awaits: the swap is one step
      _timer?.cancel();
      _renderSeq++;
      _clear();
      face = prepared;
      protection = fresh;
      originalImage = original;
      resultImage = result;
      adopted = true;
      look = firstLook;
      compare = CompareMode.result;
      _setStatus(MakeupStatus.ready);
    } catch (e) {
      debugPrint('virtual makeup: $e');
      if (!_superseded(seq)) _refuse(hadPhoto, MakeupStatus.failed);
    } finally {
      if (!adopted) {
        original?.dispose();
        result?.dispose();
      }
    }
  }

  bool _superseded(int seq) => _disposed || seq != _loadSeq;

  /// The new photo is not usable. With an earlier photo the screen stays on it.
  void _refuse(bool hadPhoto, MakeupStatus why) {
    if (hadPhoto) {
      notice = switch (why) {
        MakeupStatus.noFace => MakeupNotice.noFace,
        MakeupStatus.severalFaces => MakeupNotice.severalFaces,
        _ => MakeupNotice.failed,
      };
      _setStatus(MakeupStatus.ready);
    } else {
      _clear();
      _setStatus(why);
    }
  }

  void _clear() {
    _disposeLater(originalImage);
    _disposeLater(resultImage);
    _disposeLater(protectionOverlay);
    _disposeLater(suggestionOverlay);
    originalImage = resultImage = protectionOverlay = suggestionOverlay = null;
    face = null;
    protection = null;
    suggestion = null;
  }

  /// A picture may still be on the frame being drawn; free it after that frame.
  static void _disposeLater(ui.Image? image) {
    if (image == null) return;
    final binding = SchedulerBinding.instance;
    binding.addPostFrameCallback((_) => image.dispose());
    binding.scheduleFrame();
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
    look = look.withZone(zone, value);
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

  // ------------------------------------------------------ catalog products

  /// Opens the try-on on a catalog product (e.g. from its page). The product
  /// must have a colour; otherwise nothing is changed and false is returned.
  Future<bool> startWith(int productId) async {
    final c = catalog;
    if (c == null) return false;
    final item = await c.item(productId);
    if (_disposed || item == null || !item.canTryOn) return false;
    await applyItem(item);
    return true;
  }

  /// Shows [item] in its zone (the other zones with a product stay; zones
  /// without one are off). A product without a colour is refused.
  Future<void> applyItem(TryOnItem item) async {
    if (!item.canTryOn) return;
    if (colourMode == ColourMode.manual) {
      _manualLook = look;
      colourMode = ColourMode.catalog;
      // in catalog mode only the chosen products are on the face
      for (final z in MakeupZone.values) {
        look = look.withZone(z, look.of(z).copyWith(enabled: false));
      }
    }
    items[item.kind] = item;
    current = item;
    browseKind = item.kind;
    look = look.withZone(
      item.kind,
      ZoneLook(
        color: item.colour!,
        intensity: look.of(item.kind).intensity,
        enabled: true,
      ),
    );
    _scheduleRender();
    _notify();
    await _loadNeighbours(item);
  }

  /// Takes the product out of a zone.
  void clearItem(MakeupZone zone) {
    items.remove(zone);
    look = look.withZone(zone, look.of(zone).copyWith(enabled: false));
    if (current?.kind == zone) {
      current = items.values.isEmpty ? null : items.values.last;
      lineShades = const [];
      similar = const [];
    }
    _scheduleRender();
    _notify();
  }

  /// Back to the hand-picked colours (the products stay in memory).
  void useManualColours() {
    if (colourMode == ColourMode.manual) return;
    colourMode = ColourMode.manual;
    look = _manualLook;
    _scheduleRender();
    _notify();
  }

  /// To the products of the catalog again (what was chosen is shown again).
  void useCatalogColours() {
    if (colourMode == ColourMode.catalog || catalog == null) return;
    colourMode = ColourMode.catalog;
    _manualLook = look;
    for (final z in MakeupZone.values) {
      final it = items[z];
      look = look.withZone(
        z,
        it == null
            ? look.of(z).copyWith(enabled: false)
            : ZoneLook(
                color: it.colour!,
                intensity: look.of(z).intensity,
                enabled: true,
              ),
      );
    }
    _scheduleRender();
    _notify();
    unawaited(loadBrowse(browseKind));
  }

  /// The list of products of a kind (what the user can pick from).
  Future<void> loadBrowse(MakeupZone kind) async {
    final c = catalog;
    if (c == null) return;
    browseKind = kind;
    final list = await c.all(kind);
    if (_disposed || browseKind != kind) return;
    browseList = list;
    _notify();
  }

  Future<void> _loadNeighbours(TryOnItem item) async {
    final c = catalog;
    if (c == null) return;
    final seq = ++_neighboursSeq;
    final line = await c.sameLine(item);
    final other = await c.otherProducts(item);
    final all = await c.all(item.kind);
    if (_disposed || seq != _neighboursSeq) return;
    lineShades = line;
    similar = other;
    browseList = all;
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
    final img = await _draw(f, look, protection);
    if (_disposed || seq != _renderSeq) {
      img.dispose();
      return;
    }
    _disposeLater(resultImage);
    resultImage = img;
    _notify();
  }

  Future<ui.Image> _draw(
    PreparedFace f,
    MakeupLook l,
    ProtectionMask? p,
  ) async => PhotoDecoder.toUiImage(
    await backend.render(MakeupRequest(face: f, look: l, protection: p)),
  );

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
    _requestOverlays();
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
    _requestOverlays();
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
    _requestOverlays();
    _notify();
  }

  // The overlay pictures are rebuilt in the background. A brush can ask for a
  // new one on every pointer move: asks made while one is being built are
  // folded into ONE more round, so pictures never arrive out of order.
  bool _overlayBusy = false;
  bool _overlayDirty = false;

  void _requestOverlays() {
    _overlayDirty = true;
    if (!_overlayBusy) unawaited(_overlayLoop());
  }

  Future<void> _overlayLoop() async {
    _overlayBusy = true;
    try {
      while (_overlayDirty && !_disposed) {
        _overlayDirty = false;
        final f = face;
        if (f == null) continue;
        final w = f.image.width, h = f.image.height;
        final p = protection, s = suggestion;
        // the pixels are taken now, before any await, so they match this moment
        final pp = p != null && !p.isEmpty
            ? overlayPixels(p.data, w, h, const [34, 160, 220])
            : null;
        final sp = s != null && s.reliable && s.regions > 0
            ? overlayPixels(s.mask, w, h, const [250, 190, 40])
            : null;
        final pi = pp == null ? null : await PhotoDecoder.toUiImage(pp);
        final si = sp == null ? null : await PhotoDecoder.toUiImage(sp);
        if (_disposed || !identical(f, face)) {
          pi?.dispose();
          si?.dispose();
          continue;
        }
        _disposeLater(protectionOverlay);
        _disposeLater(suggestionOverlay);
        protectionOverlay = pi;
        suggestionOverlay = si;
        _notify();
      }
    } finally {
      _overlayBusy = false;
    }
  }

  /// A coloured, half-transparent picture of a mask, at most 360 px across.
  /// The colour is PREMULTIPLIED by the alpha, as the engine draws it: where
  /// the mask is 0 every channel is 0 (clear), where it is 255 the colour is at
  /// 55 % opacity.
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
    _disposeLater(originalImage);
    _disposeLater(resultImage);
    _disposeLater(protectionOverlay);
    _disposeLater(suggestionOverlay);
    originalImage = resultImage = protectionOverlay = suggestionOverlay = null;
    if (ownsLandmarks) unawaited(landmarks.dispose());
    super.dispose();
  }
}
