/// How urgently the cat should see a vet, as judged from the photos.
///
/// The order matters: later values are MORE urgent (except [cannotAssess],
/// which is handled separately). The safety net in [applySafetyFloor] only
/// ever moves a result UP this scale, never down.
enum Urgency {
  /// The photo can't be judged: not a cat, blurry, too dark, area hidden.
  /// This is NOT "fine" - the screen tells the owner to consult a vet if
  /// they are worried.
  cannotAssess,

  /// Nothing alarming is visible. Keep watching.
  monitorAtHome,

  /// Should be seen within a day or two.
  seeVetSoon,

  /// Needs a vet right away (within hours).
  emergency,
}

/// The structured answer of one photo check.
class HealthScreening {
  const HealthScreening({
    required this.urgency,
    required this.summary,
    this.observations = const [],
    this.possibleCauses = const [],
    this.homeCare = const [],
    this.seeVetIf = const [],
    this.photoNote,
    this.escalationReason,
  });

  final Urgency urgency;

  /// One or two plain sentences.
  final String summary;

  /// What is visibly there ("redness around the left eye").
  final List<String> observations;

  /// Things it COULD be. Never presented as a diagnosis.
  final List<String> possibleCauses;

  /// Safe, general things the owner can do meanwhile.
  final List<String> homeCare;

  /// Warning signs that mean "go to a vet".
  final List<String> seeVetIf;

  /// Photo advice, e.g. "too dark - retake in daylight".
  final String? photoNote;

  /// Set when the APP (not the AI) raised the urgency because of what the
  /// owner wrote. Shown so the owner understands why.
  final String? escalationReason;

  /// The same JSON shape the AI produces and [fromJson] reads, so a result
  /// can travel from the server to the app and back into a [HealthScreening].
  Map<String, dynamic> toJson() => {
    'urgency': switch (urgency) {
      Urgency.emergency => 'emergency',
      Urgency.seeVetSoon => 'see_vet_soon',
      Urgency.monitorAtHome => 'monitor_at_home',
      Urgency.cannotAssess => 'cannot_assess',
    },
    'summary': summary,
    'observations': observations,
    'possible_causes': possibleCauses,
    'home_care': homeCare,
    'see_vet_if': seeVetIf,
    if (photoNote != null) 'photo_note': photoNote,
  };

  HealthScreening copyWith({Urgency? urgency, String? escalationReason}) =>
      HealthScreening(
        urgency: urgency ?? this.urgency,
        summary: summary,
        observations: observations,
        possibleCauses: possibleCauses,
        homeCare: homeCare,
        seeVetIf: seeVetIf,
        photoNote: photoNote,
        escalationReason: escalationReason ?? this.escalationReason,
      );

  /// Builds a result from the AI's JSON. Tolerant: missing lists become
  /// empty, and an unknown or missing urgency becomes [Urgency.seeVetSoon]
  /// - when in doubt, be cautious.
  factory HealthScreening.fromJson(Map<String, dynamic> json) {
    List<String> strings(Object? v) => v is List
        ? v
              .whereType<String>()
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList()
        : const [];

    final note = (json['photo_note'] as String?)?.trim();
    return HealthScreening(
      urgency: _parseUrgency(json['urgency']),
      summary: ((json['summary'] as String?) ?? '').trim(),
      observations: strings(json['observations']),
      possibleCauses: strings(json['possible_causes']),
      homeCare: strings(json['home_care']),
      seeVetIf: strings(json['see_vet_if']),
      photoNote: (note == null || note.isEmpty) ? null : note,
    );
  }

  static Urgency _parseUrgency(Object? raw) {
    switch (raw) {
      case 'emergency':
        return Urgency.emergency;
      case 'see_vet_soon':
        return Urgency.seeVetSoon;
      case 'monitor_at_home':
        return Urgency.monitorAtHome;
      case 'cannot_assess':
        return Urgency.cannotAssess;
      default:
        return Urgency.seeVetSoon; // unknown -> cautious
    }
  }
}

/// Shown on every screen of the health check. Written here, in the app, so
/// the AI can never leave it out or soften it.
const screenerDisclaimer =
    'This is an AI photo check, not a veterinary diagnosis. It can miss '
    'things a vet would spot. If your cat seems unwell or in pain, or you '
    'are worried, contact a vet. Trust your instincts.';

/// Phrases that mean "emergency" whatever the photo shows. If the owner's
/// own description contains one, the result is raised to [Urgency.emergency].
///
/// This is a deliberately blunt safety net that sits AFTER the AI: models
/// can under-react, and a photo can look calm while the cat is in trouble.
/// Better a few extra "go to the vet" than one missed emergency.
const _emergencyPhrases = <String, String>{
  'trouble breathing': 'trouble breathing',
  'difficulty breathing': 'trouble breathing',
  'struggling to breathe': 'trouble breathing',
  'can\'t breathe': 'trouble breathing',
  'cant breathe': 'trouble breathing',
  'open mouth breathing': 'open-mouth breathing',
  'panting': 'panting',
  'gasping': 'gasping',
  'seizure': 'a seizure',
  'convuls': 'convulsions',
  'collaps': 'collapse',
  'unconscious': 'unconsciousness',
  'unresponsive': 'being unresponsive',
  'won\'t wake': 'not waking up',
  'not urinating': 'not urinating',
  'can\'t pee': 'trouble urinating',
  'cant pee': 'trouble urinating',
  'straining to pee': 'straining to urinate',
  'straining to urinate': 'straining to urinate',
  'no urine': 'no urine',
  'poison': 'possible poisoning',
  'toxic': 'possible poisoning',
  'antifreeze': 'antifreeze',
  // Not just 'lily': that would fire for a cat NAMED Lily.
  'lilies': 'lilies (toxic to cats)',
  'lily plant': 'a lily (toxic to cats)',
  'lily flower': 'a lily (toxic to cats)',
  'ate a lily': 'a lily (toxic to cats)',
  'ate lily': 'a lily (toxic to cats)',
  'eaten a lily': 'a lily (toxic to cats)',
  'chewed a lily': 'a lily (toxic to cats)',
  'hit by a car': 'being hit by a car',
  'hit by car': 'being hit by a car',
  'blue gums': 'blue gums',
  'pale gums': 'pale gums',
  'white gums': 'pale gums',
  'won\'t stop bleeding': 'bleeding that won\'t stop',
  'bleeding heavily': 'heavy bleeding',
  'heavy bleeding': 'heavy bleeding',
};

/// Flexible patterns for wording the exact phrases above can't catch, such
/// as "her gums look pale" or "he keeps straining in the litter box".
/// `.{0,N}` allows a few words in between.
final _emergencyPatterns = <RegExp, String>{
  RegExp(r'gums?\b.{0,25}\b(pale|white|blue|grey|gray)'): 'pale or blue gums',
  RegExp(r'(pale|white|blue|grey|gray)\b.{0,12}\bgums?'): 'pale or blue gums',
  RegExp(r'breath\w*\b.{0,20}\b(hard|heavy|heavily|fast|laboured|labored)'):
      'trouble breathing',
  RegExp(r'(laboured|labored|heavy|hard|fast)\b.{0,12}\bbreath'):
      'trouble breathing',
  RegExp(r'hard to breathe'): 'trouble breathing',
  RegExp(r'strain\w*\b.{0,30}\b(pee|urinat|litter|toilet)'):
      'straining to urinate',
  RegExp(r'(not|n\x27t|never|no)\b.{0,12}\b(peed|peeing|urinat\w*)'):
      'not urinating',
  RegExp(r'seizing|fitting|had a fit'): 'a seizure',
};

/// Raises [screening] to emergency if [ownerText] mentions a red-flag
/// phrase. Never lowers urgency. Returns the input unchanged otherwise.
HealthScreening applySafetyFloor(String ownerText, HealthScreening screening) {
  if (screening.urgency == Urgency.emergency) return screening;
  final text = ownerText.toLowerCase().replaceAll('\u2019', '\''); // ’ -> '

  String? reason;
  for (final entry in _emergencyPhrases.entries) {
    if (text.contains(entry.key)) {
      reason = entry.value;
      break;
    }
  }
  if (reason == null) {
    for (final entry in _emergencyPatterns.entries) {
      if (entry.key.hasMatch(text)) {
        reason = entry.value;
        break;
      }
    }
  }
  if (reason == null) return screening;

  return screening.copyWith(
    urgency: Urgency.emergency,
    escalationReason:
        'You mentioned $reason. That can be an emergency in '
        'cats whatever a photo shows.',
  );
}
