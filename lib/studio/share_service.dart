import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Copying text and opening the phone's share sheet. An interface so tests
/// don't need a real clipboard or share sheet.
abstract class ShareService {
  Future<void> copyText(String text);

  /// Opens the share sheet with the photo. [origin] is where the sheet
  /// should appear on iPad (ignored on phones).
  Future<void> shareImage(
    Uint8List jpegBytes, {
    required String text,
    Rect? origin,
  });
}

class SharePlusShareService implements ShareService {
  @override
  Future<void> copyText(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  @override
  Future<void> shareImage(
    Uint8List jpegBytes, {
    required String text,
    Rect? origin,
  }) async {
    // The share sheet needs a real file, so write the photo to the temporary
    // folder (the system cleans it up).
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/whiskers_post.jpg');
    await file.writeAsBytes(jpegBytes, flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'image/jpeg')],
        // Instagram ignores this text, which is why the caption is ALSO copied
        // to the clipboard first. Other apps (Messages, Mail) do use it.
        text: text,
        sharePositionOrigin: origin,
      ),
    );
  }
}
