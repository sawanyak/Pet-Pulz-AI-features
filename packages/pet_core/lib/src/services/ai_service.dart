import '../models/cat_profile.dart';
import '../models/chat_message.dart';

/// The contract every "AI brain" must follow.
///
/// The chat screen only knows about this abstract class, never about
/// Claude or Gemini specifically. That means we can swap providers, use a
/// [MockAiService] for offline development, or move to a backend server by
/// writing one new class.
abstract class AiService {
  /// Send the whole conversation so far and get the reply as a [Stream] of
  /// small text pieces ("deltas"), e.g. `"Here "`, `"are "`, `"some "`...
  ///
  /// A Stream is like a pipe that delivers values over time. The controller
  /// glues the pieces together and updates the screen after each one, so the
  /// user sees the answer being written instead of waiting for all of it.
  ///
  /// The AI has no memory between calls, so we send the full history every
  /// time. That is how it "remembers" what was said earlier.
  ///
  /// Throws [AiServiceException] (as a stream error) if something fails.
  ///
  /// [cat] and [spoken] tell the service HOW to build its hidden
  /// instructions (cat profile, and short unformatted replies when the
  /// answer will be read aloud). The service builds the prompt itself:
  /// a direct-to-provider service uses the prompt code in this package, a
  /// backend client sends these two values to the server, which builds it.
  Stream<String> replyStream(
    List<ChatMessage> history, {
    required CatProfile? cat,
    required bool spoken,
  });
}

/// Thrown by services when something goes wrong. The UI shows [message]
/// to the user in a friendly error bubble.
class AiServiceException implements Exception {
  AiServiceException(this.message);
  final String message;

  @override
  String toString() => message;
}
