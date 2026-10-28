import '../models/cat_profile.dart';
import '../models/chat_message.dart';
import 'ai_service.dart';

/// A fake AI used when no API key is configured (and in tests).
/// It lets you build and test the whole UI without internet or cost, and it
/// streams word by word so you can see the streaming UI working.
class MockAiService implements AiService {
  MockAiService({
    this.delay = const Duration(milliseconds: 900),
    this.wordDelay = const Duration(milliseconds: 40),
  });

  /// Pause before the first word (the "thinking" time).
  final Duration delay;

  /// Pause between words.
  final Duration wordDelay;

  @override
  Stream<String> replyStream(
    List<ChatMessage> history, {
    required CatProfile? cat,
    required bool spoken,
  }) async* {
    await Future<void>.delayed(delay); // pretend the AI is "thinking"
    final answer = _answerFor(history.lastWhere((m) => m.isUser).text);

    // Split into words, keeping the whitespace so Markdown layout survives.
    for (final piece in answer.split(RegExp(r'(?<=\s)'))) {
      await Future<void>.delayed(wordDelay);
      yield piece;
    }
  }

  String _answerFor(String userText) {
    final last = userText.toLowerCase();

    if (last.contains('vomit') || last.contains('blood')) {
      return 'I\'m not a vet and can\'t diagnose, but that can be serious. '
          'How long has this been going on, and is your cat still eating and '
          'drinking? If it is repeated or your cat seems weak, please '
          'contact a vet today.\n\n(Mock reply - add an API key for real answers.)';
    }
    if (last.contains('game') || last.contains('play')) {
      return '## Play ideas\n'
          'Here are some **low-effort** games for a *sleepy* cat:\n\n'
          '- **Wand toy** "hunting" sessions (10 min, end with a treat)\n'
          '- Cardboard box maze\n'
          '- Puzzle feeder for meals\n'
          '- Window perch with a bird feeder outside\n\n'
          '_(Mock reply - add an API key for real answers.)_';
    }
    return 'Hi, I\'m Whiskers! Tell me about your cat and how I can help.\n\n'
        '(Mock reply - add a key to your .env file for the real AI.)';
  }
}
