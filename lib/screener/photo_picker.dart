import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:pet_core/pet_core.dart';

enum PhotoSource { camera, gallery }

/// Thrown with a message that is safe to show to the owner.
class PhotoPickerException implements Exception {
  PhotoPickerException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Gets a photo from the camera or the photo library.
/// An interface so tests can supply photos without a camera.
abstract class PhotoPicker {
  /// Returns null if the person cancelled. [maxDimension] is the longest
  /// side in pixels the photo is shrunk to (the health check needs less
  /// detail than a photo meant to be posted).
  Future<ScreenerPhoto?> pick(PhotoSource source, {int maxDimension = 1280});
}

/// Real picker backed by the `image_picker` plugin.
class ImagePickerPhotoPicker implements PhotoPicker {
  ImagePickerPhotoPicker({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Reject anything bigger than this after shrinking (Claude's limit is
  /// 5 MB per image; we stay well below).
  static const maxBytes = 4 * 1024 * 1024;

  @override
  Future<ScreenerPhoto?> pick(
    PhotoSource source, {
    int maxDimension = 1280,
  }) async {
    try {
      final file = await _picker.pickImage(
        source: source == PhotoSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        // Shrinking BEFORE upload: a 12-megapixel photo is ~5 MB, slow to
        // send and unnecessary. 1280 px on the long side is plenty for the
        // AI (posts use 2048 so the crop stays sharp), and re-encoding to JPEG also drops most embedded metadata
        // (such as GPS location).
        maxWidth: maxDimension.toDouble(),
        maxHeight: maxDimension.toDouble(),
        imageQuality: 80,
        requestFullMetadata: false,
      );
      if (file == null) return null; // cancelled

      final bytes = await file.readAsBytes();
      if (bytes.length > maxBytes) {
        throw PhotoPickerException(
          'That photo is too large. Try a different one.',
        );
      }
      return ScreenerPhoto(bytes: bytes, mimeType: sniffMimeType(bytes));
    } on PlatformException catch (e) {
      if (e.code == 'camera_access_denied' || e.code == 'photo_access_denied') {
        throw PhotoPickerException(
          'Access was denied. Allow camera / photo access for this app in '
          'Settings.',
        );
      }
      throw PhotoPickerException(
        source == PhotoSource.camera
            ? 'The camera isn\'t available. Try choosing from your gallery.'
            : 'Couldn\'t open your photos. Please try again.',
      );
    }
  }
}

/// Works out the image format from the file's first bytes (its "magic
/// number"), because the AI APIs must be told the format and file names
/// can lie. Falls back to JPEG, what image_picker normally produces.
String sniffMimeType(Uint8List b) {
  bool starts(List<int> sig) =>
      b.length >= sig.length &&
      List.generate(sig.length, (i) => b[i] == sig[i]).every((x) => x);

  if (starts([0x89, 0x50, 0x4E, 0x47])) return 'image/png';
  if (starts([0x47, 0x49, 0x46])) return 'image/gif';
  // WebP: "RIFF" .... "WEBP"
  if (starts([0x52, 0x49, 0x46, 0x46]) &&
      b.length > 11 &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50) {
    return 'image/webp';
  }
  return 'image/jpeg';
}
