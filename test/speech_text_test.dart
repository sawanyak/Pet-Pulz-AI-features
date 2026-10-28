import 'package:flutter_test/flutter_test.dart';
import 'package:pet_care_ai/voice/speech_text.dart';

void main() {
  group('speakableText', () {
    test('strips bold, italic, headings and bullets', () {
      expect(
        speakableText('## Play ideas\n**Wand toy** and *puzzles*'),
        'Play ideas Wand toy and puzzles',
      );
      expect(speakableText('- one\n- two'), 'one two');
      expect(speakableText('* one\n* two'), 'one two');
    });

    test('keeps link text, drops URL', () {
      expect(
        speakableText('See [this guide](https://x.com/a) now'),
        'See this guide now',
      );
      expect(speakableText('Visit https://example.com today'), 'Visit today');
    });

    test('removes emoji and code', () {
      expect(speakableText('Good kitty 🐱❤️'), 'Good kitty');
      expect(speakableText('Use `catnip` carefully'), 'Use catnip carefully');
      expect(speakableText('```\ncode\n```'), '');
    });

    test('keeps numbers and normal punctuation', () {
      expect(
        speakableText('1. Feed at 7.5 grams, twice.'),
        '1. Feed at 7.5 grams, twice.',
      );
    });

    test('punctuation-only becomes empty', () {
      expect(speakableText('---'), '');
      expect(speakableText('  ...  '), '');
    });
  });

  group('splitSentences', () {
    test('returns complete sentences and keeps the unfinished tail', () {
      final r = splitSentences(
        'Cats scratch to mark territory. They also stretch. And then it be',
        minLength: 10,
      );
      expect(r.complete, [
        'Cats scratch to mark territory.',
        'They also stretch.',
      ]);
      expect(r.rest.trim(), 'And then it be');
    });

    test('a final period with no following space is NOT yet complete', () {
      final r = splitSentences('Hello there friend, how are you doing?');
      expect(r.complete, isEmpty);
      expect(r.rest, 'Hello there friend, how are you doing?');
    });

    test('decimals are not sentence ends', () {
      final r = splitSentences(
        'Give 7.5 grams of food twice a day. Next',
        minLength: 10,
      );
      expect(r.complete, ['Give 7.5 grams of food twice a day.']);
    });

    test('short fragments are merged with the next sentence', () {
      final r = splitSentences(
        'Yes! That is a great question to ask. More',
        minLength: 30,
      );
      expect(r.complete, ['Yes! That is a great question to ask.']);
    });

    test('line breaks end a piece even if short', () {
      final r = splitSentences('Play ideas\nWand toys are great.\n');
      expect(r.complete, ['Play ideas', 'Wand toys are great.']);
      expect(r.rest, '');
    });

    test('list numbers like "1." are not spoken alone', () {
      final r = splitSentences(
        '1. Set up a quiet room for the kitten.\n2. Swap scents.\n',
        minLength: 5,
      );
      expect(r.complete.first, startsWith('1. Set up'));
    });
  });
}
