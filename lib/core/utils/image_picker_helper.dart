import 'image_picker_stub.dart'
    if (dart.library.html) 'image_picker_web.dart';

/// Cross-platform helper for picking image files from gallery / file system
/// with automatic HTML file input fallback on web environments.
class ImagePickerHelper {
  static Future<String?> pickImageAsBase64() {
    return pickImageImpl();
  }
}
