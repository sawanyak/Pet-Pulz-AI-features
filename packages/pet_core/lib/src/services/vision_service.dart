import 'dart:typed_data';

import '../models/cat_profile.dart';
import '../models/health_screening.dart';

/// One photo ready to send: the encoded image file's bytes and its type.
class ScreenerPhoto {
  const ScreenerPhoto({required this.bytes, required this.mimeType});

  final Uint8List bytes;

  /// e.g. `image/jpeg` - the AI APIs need to be told the format.
  final String mimeType;
}

/// The contract of the photo health-check "AI brain" (same idea as
/// [AiService] for chat). Throws [AiServiceException] on failure.
abstract class VisionService {
  Future<HealthScreening> screen({
    required List<ScreenerPhoto> photos,
    required String concern,
    required String? duration,
    required CatProfile? cat,
  });
}
