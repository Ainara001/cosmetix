/// Real Skin Makeup, stage 1: virtual try-on of lipstick, eyeshadow and blush
/// by colour transfer, with the skin texture and a user-edited protection mask.
/// Self-contained module: the app only needs [VirtualMakeupScreen].
library;

export 'domain/face_geometry.dart';
export 'domain/face_quality.dart';
export 'domain/makeup_look.dart';
export 'engine/color_transfer_backend.dart';
export 'engine/makeup_backend.dart';
export 'engine/protection_mask.dart';
export 'engine/rgba_image.dart';
export 'landmarks/face_landmark_provider.dart';
export 'ui/virtual_makeup_screen.dart';
