import '../domain/face_geometry.dart';
import '../engine/rgba_image.dart';

/// Finds faces in a photo and returns their 478-point mesh in PIXEL
/// coordinates of that photo. The module only knows this interface: the
/// implementation (MediaPipe today) can be replaced, and tests use a fake.
abstract interface class FaceLandmarkProvider {
  /// All faces found (empty when there is none). Never guesses a face.
  Future<List<FacePoints>> detect(RgbaImage image);

  /// Frees native resources.
  Future<void> dispose();
}
