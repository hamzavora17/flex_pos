import 'dart:async';
import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
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
    debugPrint('[ImagePickerWeb] ImagePicker threw ($e). Falling back to direct HTML file input...');
  }

  // Direct HTML file input element fallback for web environments
  final completer = Completer<String?>();
  final html.FileUploadInputElement uploadInput = html.FileUploadInputElement();
  uploadInput.accept = 'image/*';
  uploadInput.click();

  uploadInput.onChange.listen((e) {
    final files = uploadInput.files;
    if (files != null && files.isNotEmpty) {
      final file = files[0];
      final reader = html.FileReader();
      reader.readAsDataUrl(file);
      reader.onLoadEnd.listen((e) {
        final result = reader.result;
        if (result != null) {
          completer.complete(result.toString());
        } else {
          completer.complete(null);
        }
      });
    } else {
      completer.complete(null);
    }
  });

  return completer.future;
}
