import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_tts/flutter_tts.dart';

import 'speech_io.dart';

/// [SpeechOutput] backed by the `flutter_tts` plugin (the phone's built-in
/// voice: AVSpeechSynthesizer on iOS, Android's TextToSpeech).
class FlutterTtsOutput implements SpeechOutput {
  FlutterTts? _tts; // created lazily
  Completer<void>? _current; // completes when the current sentence is over

  @override
  Future<void> initialize() async {
    final tts = _tts = FlutterTts();
    // Whatever way a sentence ends - finished, cancelled or failed - the
    // waiting speak() call must be released, or the conversation would hang.
    tts.setCompletionHandler(_finish);
    tts.setCancelHandler(_finish);
    tts.setErrorHandler((_) => _finish());
  }

  @override
  Future<void> prepare() async {
    // Listening switches the iPhone's audio into "recording" mode, which can
    // leave speech quiet or on the earpiece. Re-select speaker playback
    // (while still allowing the mic) before we talk.
    if (!Platform.isIOS) return;
    try {
      await _tts?.setSharedInstance(true);
      await _tts
          ?.setIosAudioCategory(IosTextToSpeechAudioCategory.playAndRecord, [
            IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
            IosTextToSpeechAudioCategoryOptions.allowBluetooth,
            IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          ]);
    } catch (_) {
      // Audio routing is best-effort; speaking still works without it.
    }
  }

  @override
  Future<void> speak(String text) async {
    final tts = _tts;
    if (tts == null) return;
    final done = _current = Completer<void>();
    await tts.speak(text);
    // Safety net: never wait forever if the engine forgets to call back.
    await done.future.timeout(const Duration(seconds: 120), onTimeout: () {});
  }

  @override
  Future<void> stop() async {
    try {
      await _tts?.stop();
    } catch (_) {}
    _finish();
  }

  void _finish() {
    final c = _current;
    _current = null;
    if (c != null && !c.isCompleted) c.complete();
  }
}
