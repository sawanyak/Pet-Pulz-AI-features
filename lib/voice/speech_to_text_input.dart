import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'speech_io.dart';

/// [SpeechInput] backed by the `speech_to_text` plugin, which uses the
/// phone's own recogniser (Apple Speech on iOS, Google's on Android).
///
/// The plugin reports things through several separate callbacks (results,
/// status changes, errors) that don't always arrive in a tidy order. This
/// class folds them into the simple contract "one session ends with exactly
/// one final result or one failure".
class SpeechToTextInput implements SpeechInput {
  SpeechToText? _stt; // created lazily so merely building the app is free

  SpeechResultCallback? _onResult;
  SpeechFailureCallback? _onFailure;
  String _lastWords = '';
  bool _delivered = false; // has this session already ended?

  @override
  Future<bool> initialize() async {
    try {
      final stt = _stt ??= SpeechToText();
      // Shows the microphone + speech-recognition permission pop-ups the
      // first time. Returns false if denied or no recogniser exists.
      return await stt.initialize(
        onError: _handleError,
        onStatus: _handleStatus,
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> start({
    required SpeechResultCallback onResult,
    required SpeechFailureCallback onFailure,
  }) async {
    _onResult = onResult;
    _onFailure = onFailure;
    _lastWords = '';
    _delivered = false;
    try {
      await _stt!.listen(
        onResult: _handleResult,
        listenOptions: SpeechListenOptions(
          partialResults: true, // live transcript while talking
          cancelOnError: true,
          listenMode: ListenMode.dictation, // sentences, not one word
          pauseFor: const Duration(seconds: 3), // silence = "I'm done"
          listenFor: const Duration(seconds: 45), // hard cap per question
        ),
      );
    } catch (_) {
      _end(failure: SpeechFailure.other);
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _stt?.stop();
    } catch (_) {}
  }

  @override
  Future<void> cancel() async {
    _onResult = null; // late events from the plugin are ignored
    _onFailure = null;
    _delivered = true;
    try {
      await _stt?.cancel();
    } catch (_) {}
  }

  void _handleResult(SpeechRecognitionResult r) {
    _lastWords = r.recognizedWords;
    if (r.finalResult) {
      _end(finalText: _lastWords);
    } else {
      _onResult?.call(SpeechResult(_lastWords, isFinal: false));
    }
  }

  /// 'done' arrives when the session is over. Normally the final result came
  /// first; if not (a known quirk), fall back to whatever we heard.
  void _handleStatus(String status) {
    if (status != SpeechToText.doneStatus || _delivered) return;
    if (_lastWords.trim().isNotEmpty) {
      _end(finalText: _lastWords);
    } else {
      _end(failure: SpeechFailure.noSpeech);
    }
  }

  void _handleError(SpeechRecognitionError e) {
    if (_delivered) return;
    final msg = e.errorMsg.toLowerCase();
    if (msg.contains('permission')) {
      _end(failure: SpeechFailure.permission);
    } else if (msg.contains('no_match') || msg.contains('timeout')) {
      // "Didn't catch that" - but if we did hear words, use them.
      _lastWords.trim().isNotEmpty
          ? _end(finalText: _lastWords)
          : _end(failure: SpeechFailure.noSpeech);
    } else {
      _end(failure: SpeechFailure.other);
    }
  }

  /// Ends the session exactly once.
  void _end({String? finalText, SpeechFailure? failure}) {
    if (_delivered) return;
    _delivered = true;
    if (finalText != null) {
      _onResult?.call(SpeechResult(finalText, isFinal: true));
    } else {
      _onFailure?.call(failure ?? SpeechFailure.other);
    }
  }
}
