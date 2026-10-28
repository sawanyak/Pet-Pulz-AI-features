// The two "ears and mouth" contracts for voice mode.
//
// Like [AiService] for the AI, these interfaces hide the real plugins from
// the rest of the app. The voice logic only knows "start listening" and
// "say this", so we can test the whole conversation loop with fakes (no
// microphone needed) and swap plugins later without touching it.

/// One piece of recognised speech.
class SpeechResult {
  const SpeechResult(this.text, {required this.isFinal});

  /// Everything recognised so far in this listening session.
  final String text;

  /// False while the person is still talking (a live, changing draft);
  /// true once the recogniser considers the sentence complete.
  final bool isFinal;
}

/// Why listening ended without usable speech.
enum SpeechFailure {
  /// Nobody said anything (or it wasn't understood). Normal and retryable.
  noSpeech,

  /// The user refused microphone / speech-recognition access.
  permission,

  /// Anything else: no recogniser on the device, busy, network...
  other,
}

typedef SpeechResultCallback = void Function(SpeechResult result);
typedef SpeechFailureCallback = void Function(SpeechFailure failure);

/// Speech-to-text.
abstract class SpeechInput {
  /// Prepares the recogniser and asks for microphone / speech permission
  /// (the OS shows its pop-up the first time). Returns false if voice input
  /// can't be used.
  Future<bool> initialize();

  /// Starts one listening session. Exactly one of these ends it:
  /// a result with `isFinal: true`, or a failure.
  Future<void> start({
    required SpeechResultCallback onResult,
    required SpeechFailureCallback onFailure,
  });

  /// Ends the session early, keeping what was heard (delivered as final).
  Future<void> stop();

  /// Ends the session and throws away everything, with no callbacks.
  Future<void> cancel();
}

/// Text-to-speech.
abstract class SpeechOutput {
  Future<void> initialize();

  /// Called once before a reply is spoken (re-selects the audio route,
  /// because listening changes it).
  Future<void> prepare();

  /// Speaks [text] and completes when it has FINISHED (or was stopped).
  Future<void> speak(String text);

  /// Cuts off any speech immediately.
  Future<void> stop();
}
