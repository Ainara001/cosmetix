import 'face_geometry.dart';

/// Why a photo may give an inaccurate result. None of these changes the photo:
/// they only tell the user not to trust the result as much.
enum QualityIssue {
  /// More than one face: the module cannot know which one to use.
  severalFaces,

  /// The head is turned: lips, cheeks and eyelids may be placed less precisely.
  turnedHead,

  /// The head is tilted.
  tiltedHead,

  /// The face is small in the photo: the zones are made of few pixels.
  smallFace,
}

/// What the module found about the face in a photo.
class FaceQuality {
  const FaceQuality({required this.faceCount, this.issues = const {}});

  final int faceCount;
  final Set<QualityIssue> issues;

  bool get hasFace => faceCount > 0;

  /// The try-on is not run for several faces (it would be a guess).
  bool get canRun => faceCount == 1;

  /// True when the result should be marked as less reliable.
  bool get lowReliability => issues.any((i) => i != QualityIssue.severalFaces);

  static const maxYawRatio = 1.5;
  static const minYawRatio = 0.65;
  static const maxRollDegrees = 20.0;
  static const minFaceWidthFraction = 0.2;

  /// Looks at one face found in an image [imageWidth] pixels wide.
  static FaceQuality assess(FacePoints face, int imageWidth, {int count = 1}) {
    final issues = <QualityIssue>{};
    if (count > 1) issues.add(QualityIssue.severalFaces);
    final yaw = face.yawRatio;
    if (yaw > maxYawRatio || yaw < minYawRatio) {
      issues.add(QualityIssue.turnedHead);
    }
    if (face.rollDegrees.abs() > maxRollDegrees) {
      issues.add(QualityIssue.tiltedHead);
    }
    if (face.faceWidth / imageWidth < minFaceWidthFraction) {
      issues.add(QualityIssue.smallFace);
    }
    return FaceQuality(faceCount: count, issues: issues);
  }
}
