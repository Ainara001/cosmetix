import '../domain/face_geometry.dart';
import '../domain/face_quality.dart';
import '../domain/makeup_look.dart';
import 'polygon_raster.dart';
import 'protection_mask.dart';
import 'rgba_image.dart';
import 'zone_masks.dart';

/// What a backend can do. Stage 1 has one backend (colour transfer). A later
/// backend (for example a generative model that copies the makeup of a
/// REFERENCE photo) implements the same interface and says so here.
class BackendCapabilities {
  const BackendCapabilities({
    required this.supportsReference,
    required this.runsOnDevice,
  });

  /// Can the backend copy a look from a reference photo?
  final bool supportsReference;

  /// Does the photo stay on the phone?
  final bool runsOnDevice;
}

/// One photo, ready to be made up: the pixels, the face mesh, the zone masks
/// and what was found about the face.
class PreparedFace {
  PreparedFace({
    required this.image,
    required this.points,
    required this.masks,
    required this.quality,
  });

  /// Detects nothing: the points come from a landmark provider.
  factory PreparedFace.from(
    RgbaImage image,
    FacePoints points, {
    int faceCount = 1,
  }) => PreparedFace(
    image: image,
    points: points,
    masks: ZoneMaskBuilder.build(points, image.width, image.height),
    quality: FaceQuality.assess(points, image.width, count: faceCount),
  );

  final RgbaImage image;
  final FacePoints points;
  final ZoneMasks masks;
  final FaceQuality quality;

  MaskPatch maskOf(MakeupZone zone) => switch (zone) {
    MakeupZone.lips => masks.lips,
    MakeupZone.eyeshadow => masks.eyeshadow,
    MakeupZone.blush => masks.blush,
  };

  /// Backends keep their per-photo caches here.
  final Map<String, Object> cache = {};
}

/// What a backend gets for one render.
class MakeupRequest {
  const MakeupRequest({
    required this.face,
    required this.look,
    this.protection,
    this.reference,
  });

  final PreparedFace face;
  final MakeupLook look;

  /// Pixels that must stay exactly as in the photo.
  final ProtectionMask? protection;

  /// A reference photo for backends that can copy a look (see capabilities).
  final RgbaImage? reference;
}

/// The contract every makeup engine keeps:
///
/// 1. the result has the size of the photo;
/// 2. a pixel with protection 1, or outside every zone, is returned byte for
///    byte as in the photo;
/// 3. the photo is NOT smoothed, retouched or cleaned: pores, acne, scars and
///    redness stay (the engine only shifts colours, it never filters pixels).
abstract interface class MakeupBackend {
  String get id;
  BackendCapabilities get capabilities;

  Future<RgbaImage> render(MakeupRequest request);
}
