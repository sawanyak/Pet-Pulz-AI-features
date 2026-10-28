/// Enums for the multiple-choice fields. Using enums (instead of free text
/// like "male") means the form can't produce a typo and the AI prompt
/// always gets a value we understand.
enum CatSex { female, male, unknown }

enum NeuterStatus { yes, no, unknown }

enum CatLifestyle { indoor, outdoor, both }

/// Everything the app knows about the user's cat.
///
/// Immutable, like [ChatMessage]: to change something you build a new
/// profile. It converts to and from JSON so it can be saved on the phone.
class CatProfile {
  const CatProfile({
    required this.name,
    this.ageYears = 0,
    this.ageMonths = 0,
    this.breed = '',
    this.sex = CatSex.unknown,
    this.neuter = NeuterStatus.unknown,
    this.weightKg,
    this.lifestyle = CatLifestyle.indoor,
    this.notes = '',
  });

  final String name;
  final int ageYears;
  final int ageMonths; // 0-11, the "extra" months beyond ageYears
  final String breed;
  final CatSex sex;
  final NeuterStatus neuter;
  final double? weightKg;
  final CatLifestyle lifestyle;

  /// Free text: personality, health conditions, medication, allergies...
  final String notes;

  bool get hasAge => ageYears > 0 || ageMonths > 0;

  /// Short human-readable age such as "3 yrs", "8 mos" or "1 yr 4 mos".
  String get ageLabel {
    final parts = [
      if (ageYears > 0) '$ageYears ${ageYears == 1 ? 'yr' : 'yrs'}',
      if (ageMonths > 0) '$ageMonths ${ageMonths == 1 ? 'mo' : 'mos'}',
    ];
    return parts.join(' ');
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'ageYears': ageYears,
    'ageMonths': ageMonths,
    'breed': breed,
    'sex': sex.name,
    'neuter': neuter.name,
    'weightKg': weightKg,
    'lifestyle': lifestyle.name,
    'notes': notes,
  };

  /// Tolerant on purpose: a missing or unexpected field falls back to a
  /// default instead of crashing, so an older saved profile still loads
  /// after we add new fields in a future version.
  factory CatProfile.fromJson(Map<String, dynamic> json) => CatProfile(
    name: (json['name'] as String?) ?? '',
    ageYears: (json['ageYears'] as num?)?.toInt() ?? 0,
    ageMonths: (json['ageMonths'] as num?)?.toInt() ?? 0,
    breed: (json['breed'] as String?) ?? '',
    sex: _enumFrom(CatSex.values, json['sex'], CatSex.unknown),
    neuter: _enumFrom(
      NeuterStatus.values,
      json['neuter'],
      NeuterStatus.unknown,
    ),
    weightKg: (json['weightKg'] as num?)?.toDouble(),
    lifestyle: _enumFrom(
      CatLifestyle.values,
      json['lifestyle'],
      CatLifestyle.indoor,
    ),
    notes: (json['notes'] as String?) ?? '',
  );
}

T _enumFrom<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}
