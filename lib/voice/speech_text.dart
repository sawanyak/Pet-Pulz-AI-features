// Helpers that turn the AI's written (Markdown) reply into text that
// sounds natural when read aloud.

/// Splits streamed text into finished sentences plus an unfinished rest.
///
/// While the AI is still writing, the end of the text is a half-sentence
/// ("Cats scratch to mark ter"). We only want to speak COMPLETE sentences,
/// so we cut at sentence ends and hand back the leftover (exactly as it was,
/// so callers can count characters) to try again when
/// more text has arrived.
///
/// A sentence ends at `. ! ? …` followed by whitespace, or at a line break.
/// Tiny fragments (shorter than [minLength]) are glued to the next sentence,
/// because speaking "Yes!" and then pausing sounds choppy.
({List<String> complete, String rest}) splitSentences(
  String text, {
  int minLength = 30,
}) {
  final complete = <String>[];
  var start = 0;

  // group(1) matches punctuation ends; a bare "\n" is the other alternative.
  final boundary = RegExp(r'([.!?…]+["\x27)\]*_]*)(?=\s)|\n');
  final listNumber = RegExp(r'^\s*(?:[-*•]\s*)?\d+\.$');

  for (final m in boundary.allMatches(text)) {
    final piece = text.substring(start, m.end);
    final trimmed = piece.trim();
    if (trimmed.isEmpty) {
      start = m.end;
      continue;
    }
    // "1." at the start of a list item is not a sentence end.
    if (listNumber.hasMatch(trimmed)) continue;
    // Too short to speak alone (but a line break always ends a piece).
    final isLineBreak = m.group(1) == null;
    if (!isLineBreak && trimmed.length < minLength) continue;

    complete.add(trimmed);
    start = m.end;
  }
  return (complete: complete, rest: text.substring(start));
}

/// Removes Markdown symbols, links and emoji so a speech engine doesn't
/// say "asterisk asterisk" or "cat face". Returns '' if nothing speakable
/// is left.
String speakableText(String markdown) {
  var t = markdown;

  t = t.replaceAll(RegExp(r'```[\s\S]*?```'), ' '); // code blocks
  t = t.replaceAllMapped(
    RegExp(r'!?\[([^\]]*)\]\([^)]*\)'),
    (m) => m.group(1) ?? '',
  ); // links
  t = t.replaceAll(RegExp(r'https?://\S+'), ''); // bare URLs
  t = t.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), ''); // #
  t = t.replaceAll(RegExp(r'^\s*[-*+•]\s+', multiLine: true), ''); // bullets
  t = t.replaceAll(RegExp(r'^\s*>\s?', multiLine: true), ''); // quotes
  t = t.replaceAll(RegExp(r'[*_`~]+'), ''); // bold / italic / code marks
  t = t.replaceAll(
    RegExp(
      r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{200D}]',
      unicode: true,
    ),
    '',
  ); // emoji
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();

  // Nothing pronounceable left (only punctuation)? Skip it.
  return RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(t) ? t : '';
}
