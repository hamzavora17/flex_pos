import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

Future<String?> pickImageImpl() async {
  try {
    final ImagePicker picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      return 'data:image/png;base64,${base64Encode(bytes)}';
    }
  } catch (e) {
    debugPrint('Error picking image: $e');
    rethrow;
  }
  return null;
}
