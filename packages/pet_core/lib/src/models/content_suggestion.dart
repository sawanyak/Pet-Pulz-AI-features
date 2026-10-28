/// The mood the AI reads from a photo. Each mood also carries the emoji shown
/// in the app and a "sound vibe": the kind of music that would suit it, for
/// when we add audio to video Reels.
enum PetMood {
  playful('Playful', '\u{1F63A}', 'bouncy ukulele, upbeat and light'),
  sleepy('Sleepy', '\u{1F634}', 'soft lo-fi piano, slow and dreamy'),
  mischievous('Mischievous', '\u{1F608}', 'sneaky pizzicato strings'),
  curious('Curious', '\u{1F9D0}', 'gentle marimba, wondering and bright'),
  cozy('Cozy', '\u{2615}', 'warm acoustic guitar, fireside calm'),
  chaotic('Chaotic', '\u{1F4A5}', 'fast quirky beats, cartoon energy'),
  regal('Regal', '\u{1F451}', 'grand orchestral swell, dramatic'),
  grumpy('Grumpy', '\u{1F620}', 'deadpan low bass, dry and funny'),
  sweet('Sweet', '\u{1F970}', 'tender music-box melody');

  const PetMood(this.label, this.emoji, this.soundVibe);

  final String label;
  final String emoji;
  final String soundVibe;

  static PetMood fromName(Object? name) {
    for (final m in values) {
      if (m.name == name) return m;
    }
    return PetMood.sweet;
  }
}

/// One caption the owner can choose.
class CaptionOption {
  const CaptionOption({required this.tone, required this.text});

  /// "funny", "sweet", "witty"...
  final String tone;
  final String text;
}

/// Instagram's limits. Going over makes the post fail, so we enforce them.
const instagramMaxCaptionLength = 2200;
const instagramMaxHashtags = 30;

/// Everything the AI suggests for one photo.
class ContentSuggestion {
  const ContentSuggestion({
    required this.mood,
    required this.captions,
    required this.hashtags,
    this.focusX = 0.5,
    this.focusY = 0.5,
    this.subject = '',
  });

  final PetMood mood;
  final List<CaptionOption> captions;

  /// Hashtags WITHOUT the leading "#".
  final List<String> hashtags;

  /// Where the pet's face is, as fractions of the photo (0,0 = top-left).
  /// The crop is centred on this point so the cat stays in frame.
  final double focusX;
  final double focusY;

  /// Short description of the photo ("a ginger cat asleep on a windowsill").
  final String subject;

  /// The JSON shape [fromJson] reads (used to send results to the app).
  Map<String, dynamic> toJson() => {
    'mood': mood.name,
    'focus': {'x': focusX, 'y': focusY},
    'subject': subject,
    'captions': [
      for (final c in captions) {'tone': c.tone, 'text': c.text},
    ],
    'hashtags': hashtags,
  };

  /// Tolerant parser for the AI's JSON: clamps numbers, drops junk, and
  /// falls back to safe defaults instead of throwing.
  factory ContentSuggestion.fromJson(Map<String, dynamic> json) {
    double unit(Object? v) =>
        v is num ? v.toDouble().clamp(0.0, 1.0).toDouble() : 0.5;

    final focus = json['focus'];
    final captions = <CaptionOption>[];
    for (final c in (json['captions'] as List? ?? const [])) {
      if (c is! Map) continue;
      var text = ((c['text'] as String?) ?? '').trim();
      if (text.isEmpty) continue;
      if (text.length > instagramMaxCaptionLength) {
        text = text.substring(0, instagramMaxCaptionLength);
      }
      captions.add(
        CaptionOption(
          tone: ((c['tone'] as String?) ?? '').trim().toLowerCase(),
          text: text,
        ),
      );
    }

    return ContentSuggestion(
      mood: PetMood.fromName(json['mood']),
      captions: captions.take(5).toList(),
      hashtags: normalizeHashtags(json['hashtags']),
      focusX: focus is Map ? unit(focus['x']) : 0.5,
      focusY: focus is Map ? unit(focus['y']) : 0.5,
      subject: ((json['subject'] as String?) ?? '').trim(),
    );
  }
}

/// Cleans the AI's hashtag list: removes "#", spaces and punctuation, drops
/// too-short or too-long tags and duplicates (ignoring case), and stops at
/// [instagramMaxHashtags].
List<String> normalizeHashtags(Object? raw) {
  if (raw is! List) return const [];
  final seen = <String>{};
  final out = <String>[];
  for (final item in raw) {
    if (item is! String) continue;
    final tag = item.replaceAll(RegExp(r'[^\p{L}\p{N}_]', unicode: true), '');
    if (tag.length < 2 || tag.length > 40) continue;
    if (!seen.add(tag.toLowerCase())) continue;
    out.add(tag);
    if (out.length == instagramMaxHashtags) break;
  }
  return out;
}

/// The text to paste into Instagram: caption, blank line, hashtags.
String composePost(String caption, Iterable<String> hashtags) {
  final tags = hashtags.take(instagramMaxHashtags).map((t) => '#$t').join(' ');
  final text = caption.trim();
  if (tags.isEmpty) return text;
  if (text.isEmpty) return tags;
  return '$text\n\n$tags';
}
