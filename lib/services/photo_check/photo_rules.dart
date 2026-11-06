/// Why a photo is not accepted (or is accepted with a warning). One value per
/// reason, so the screen can pick the text and the tests can name the reason.
enum PhotoIssue {
  /// The file is empty, damaged or not a picture.
  unreadable,

  /// No face was found.
  noFace,

  /// The check itself failed (the face detector raised an error). The photo is
  /// treated as not checked, and a photo that was not checked is not sent.
  checkFailed,

  /// Another face about as large as the main one.
  severalFaces,

  /// A smaller face somewhere in the frame (a bystander).
  backgroundFace,

  /// The face is small: few pixels to judge the colour from.
  faceSmall,
  blurry,
  tooDark,
  overexposed,

  /// Black and white: the colour of the skin cannot be judged at all.
  grayscale,

  /// The head is turned.
  turned,

  /// The eyes look covered by dark lenses.
  eyesCovered,

  /// Little of the face is the colour of the skin: hair, a beard, a mask or a deep shadow.
  littleSkin,

  /// Strong side light: one cheek much brighter than the other.
  unevenLight,
}

enum PhotoLevel { ok, warn, reject }

/// One reason with the measured value behind it (for logs and tests; the user
/// sees only the text of the [issue]).
class PhotoReason {
  const PhotoReason(this.issue, this.level, [this.value]);

  final PhotoIssue issue;
  final PhotoLevel level;
  final double? value;

  @override
  String toString() =>
      '${level.name}:${issue.name}${value == null ? '' : '($value)'}';
}

/// The result of the local check. [level] is the worst of the reasons.
class PhotoVerdict {
  PhotoVerdict(this.reasons)
    : level = reasons.fold(
        PhotoLevel.ok,
        (w, r) => r.level.index > w.index ? r.level : w,
      ),
      _single = null;

  const PhotoVerdict.reject(PhotoIssue issue)
    : reasons = const [],
      level = PhotoLevel.reject,
      _single = issue;

  final List<PhotoReason> reasons;
  final PhotoLevel level;
  final PhotoIssue? _single;

  bool get accepted => level != PhotoLevel.reject;
  bool get isOk => level == PhotoLevel.ok;

  /// The issues to show, worst first.
  List<PhotoIssue> get issues {
    if (_single != null) return [_single];
    final sorted = [...reasons]..sort((a, b) => b.level.index - a.level.index);
    return [for (final r in sorted) r.issue];
  }

  @override
  String toString() => 'PhotoVerdict(${level.name}, ${_single ?? reasons})';
}

/// What was measured on the face (all in the units of the Python stand,
/// `tools/eval/photo_quality.py`, which is the reference for these numbers).
class PhotoMetrics {
  const PhotoMetrics({
    required this.faceCount,
    required this.facePx,
    required this.sharpness,
    required this.faceP95Luma,
    required this.skinChroma,
    required this.clippedPct,
    required this.crushedPct,
    required this.lrAsym,
    required this.yawOffset,
    required this.rollDeg,
    required this.secondFaceRatio,
    required this.eyeDarkRatio,
    required this.eyeContrast,
    required this.skinVisible,
  });

  final int faceCount;
  final double facePx;
  final double sharpness;
  final double faceP95Luma;
  final double skinChroma;
  final double clippedPct;
  final double crushedPct;
  final double lrAsym;
  final double yawOffset;
  final double rollDeg;
  final double secondFaceRatio;
  final double eyeDarkRatio;
  final double eyeContrast;
  final double skinVisible;

  Map<String, Object?> toJson() => {
    'faces': faceCount,
    'face_px': facePx,
    'sharpness': sharpness,
    'face_p95_luma': faceP95Luma,
    'skin_chroma': skinChroma,
    'clipped_pct': clippedPct,
    'crushed_pct': crushedPct,
    'lr_asym': lrAsym,
    'yaw_offset': yawOffset,
    'roll_deg': rollDeg,
    'second_face_ratio': secondFaceRatio,
    'eye_dark_ratio': eyeDarkRatio,
    'eye_contrast': eyeContrast,
    'skin_visible': skinVisible,
  };
}

/// The thresholds. Same numbers as `T` in `tools/eval/photo_quality.py`; they
/// were chosen on the development photos (24 + 52) and synthetic defects and
/// checked on a separate, fresh evaluation set (see docs/photo-check-report.md).
class PhotoThresholds {
  PhotoThresholds._();

  // (warn, reject)
  static const facePxMin = (160.0, 100.0);
  static const sharpnessMin = (60.0, 25.0);

  /// Brightest 5% of the face. Relative to nothing but the face itself, so a
  /// dark skin tone in good light (about 150 and up) is not mistaken for a
  /// dark photo; a really dark photo is below 110.
  static const faceP95LumaMin = (110.0, 80.0);
  static const skinChromaMin = (3.0, 2.0);
  static const clippedPctMax = (4.0, 12.0);
  static const crushedPctMax = (25.0, 50.0);
  static const yawOffsetMax = (0.15, 0.25);

  /// Side light is only ever a warning.
  static const lrAsymWarn = 0.35;

  /// Another face: any is a warning, one this much of the main face's width rejects.
  static const secondFaceReject = 0.25;

  /// Eyes darker than the cheeks and flat: opaque dark lenses.
  static const eyeDarkMax = 0.8;
  static const eyeContrastMax = 0.07;

  /// Warn only: a beard, hair or a deep shadow lowers it.
  static const skinVisibleWarn = 0.5;

  /// Which reasons a photo has, given what was measured.
  static PhotoVerdict judge(PhotoMetrics m) {
    final r = <PhotoReason>[];
    void low(PhotoIssue i, double v, (double, double) t) {
      if (v.isNaN) return;
      if (v < t.$2) {
        r.add(PhotoReason(i, PhotoLevel.reject, v));
      } else if (v < t.$1) {
        r.add(PhotoReason(i, PhotoLevel.warn, v));
      }
    }

    void high(PhotoIssue i, double v, (double, double) t) {
      if (v.isNaN) return;
      if (v > t.$2) {
        r.add(PhotoReason(i, PhotoLevel.reject, v));
      } else if (v > t.$1) {
        r.add(PhotoReason(i, PhotoLevel.warn, v));
      }
    }

    if (m.secondFaceRatio >= secondFaceReject) {
      r.add(
        PhotoReason(
          PhotoIssue.severalFaces,
          PhotoLevel.reject,
          m.secondFaceRatio,
        ),
      );
    } else if (m.secondFaceRatio > 0) {
      r.add(
        PhotoReason(
          PhotoIssue.backgroundFace,
          PhotoLevel.warn,
          m.secondFaceRatio,
        ),
      );
    }
    if (!m.eyeDarkRatio.isNaN &&
        !m.eyeContrast.isNaN &&
        m.eyeDarkRatio < eyeDarkMax &&
        m.eyeContrast < eyeContrastMax) {
      r.add(
        PhotoReason(PhotoIssue.eyesCovered, PhotoLevel.reject, m.eyeContrast),
      );
    }
    if (!m.skinVisible.isNaN && m.skinVisible < skinVisibleWarn) {
      r.add(PhotoReason(PhotoIssue.littleSkin, PhotoLevel.warn, m.skinVisible));
    }
    low(PhotoIssue.faceSmall, m.facePx, facePxMin);
    low(PhotoIssue.blurry, m.sharpness, sharpnessMin);
    low(PhotoIssue.grayscale, m.skinChroma, skinChromaMin);
    low(PhotoIssue.tooDark, m.faceP95Luma, faceP95LumaMin);
    high(PhotoIssue.overexposed, m.clippedPct, clippedPctMax);
    high(PhotoIssue.tooDark, m.crushedPct, crushedPctMax);
    high(PhotoIssue.turned, m.yawOffset, yawOffsetMax);
    if (!m.lrAsym.isNaN && m.lrAsym > lrAsymWarn) {
      r.add(PhotoReason(PhotoIssue.unevenLight, PhotoLevel.warn, m.lrAsym));
    }
    return PhotoVerdict(r);
  }
}
