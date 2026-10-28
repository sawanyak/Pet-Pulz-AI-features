import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:pet_core/pet_core.dart';
import '../theme/pet_pulz_theme.dart';
import 'cat_profile_store.dart';

/// The form where the owner describes their cat.
class CatProfileScreen extends StatefulWidget {
  const CatProfileScreen({super.key, required this.store});

  final CatProfileStore store;

  @override
  State<CatProfileScreen> createState() => _CatProfileScreenState();
}

class _CatProfileScreenState extends State<CatProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  late final _name = TextEditingController();
  late final _years = TextEditingController();
  late final _months = TextEditingController();
  late final _breed = TextEditingController();
  late final _weight = TextEditingController();
  late final _notes = TextEditingController();

  CatSex _sex = CatSex.unknown;
  NeuterStatus _neuter = NeuterStatus.unknown;
  CatLifestyle _lifestyle = CatLifestyle.indoor;

  bool get _isEditing => widget.store.profile != null;

  @override
  void initState() {
    super.initState();
    final p = widget.store.profile;
    if (p == null) return;
    _name.text = p.name;
    _years.text = p.ageYears > 0 ? '${p.ageYears}' : '';
    _months.text = p.ageMonths > 0 ? '${p.ageMonths}' : '';
    _breed.text = p.breed;
    final w = p.weightKg;
    _weight.text = w == null
        ? ''
        : (w == w.roundToDouble() ? w.toInt().toString() : w.toString());
    _notes.text = p.notes;
    _sex = p.sex;
    _neuter = p.neuter;
    _lifestyle = p.lifestyle;
  }

  @override
  void dispose() {
    for (final c in [_name, _years, _months, _breed, _weight, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    await widget.store.save(
      CatProfile(
        name: _name.text.trim(),
        ageYears: int.tryParse(_years.text) ?? 0,
        ageMonths: int.tryParse(_months.text) ?? 0,
        breed: _breed.text.trim(),
        sex: _sex,
        neuter: _neuter,
        weightKg: _parseWeight(_weight.text),
        lifestyle: _lifestyle,
        notes: _notes.text.trim(),
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete profile?'),
        content: const Text(
          'Whiskers will forget your cat\'s details. Your chat stays.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.store.clear();
    if (mounted) Navigator.of(context).pop();
  }

  static double? _parseWeight(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PetPulzTheme.bgGradientTop,
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Your Cat Profile' : 'Add Your Pet',
          style: const TextStyle(fontWeight: FontWeight.bold, color: PetPulzTheme.textDark),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _save,
              child: const Text('Save'),
            ),
          ),
          if (_isEditing)
            IconButton(
              tooltip: 'Delete profile',
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              onPressed: _delete,
            ),
        ],
      ),
      body: PetPulzBackground(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              _PrivacyNote(),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name *',
                ),
                maxLength: 40,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Please enter a name'
                    : null,
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _years,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Age (years)',
                      ),
                      validator: (v) => _intInRange(v, 0, 30, 'Max 30'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _months,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'and months',
                      ),
                      validator: (v) => _intInRange(v, 0, 11, '0-11'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _breed,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Breed (e.g. Domestic Shorthair)',
                ),
                maxLength: 40,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _weight,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Weight',
                  suffixText: 'kg',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final w = _parseWeight(v);
                  if (w == null) return 'Enter a number, e.g. 4.5';
                  if (w < 0.3 || w > 15) return 'Between 0.3 and 15 kg';
                  return null;
                },
              ),
              const SizedBox(height: 20),
              _Choice<CatSex>(
                label: 'Sex',
                value: _sex,
                options: const {
                  CatSex.female: 'Female',
                  CatSex.male: 'Male',
                  CatSex.unknown: 'Unknown',
                },
                onChanged: (v) => setState(() => _sex = v),
              ),
              _Choice<NeuterStatus>(
                label: 'Neutered / Spayed',
                value: _neuter,
                options: const {
                  NeuterStatus.yes: 'Yes',
                  NeuterStatus.no: 'No',
                  NeuterStatus.unknown: 'Not sure',
                },
                onChanged: (v) => setState(() => _neuter = v),
              ),
              _Choice<CatLifestyle>(
                label: 'Environment / Lifestyle',
                value: _lifestyle,
                options: const {
                  CatLifestyle.indoor: 'Indoors',
                  CatLifestyle.outdoor: 'Outdoors',
                  CatLifestyle.both: 'Both',
                },
                onChanged: (v) => setState(() => _lifestyle = v),
              ),
              const SizedBox(height: 4),
              TextFormField(
                controller: _notes,
                minLines: 3,
                maxLines: 6,
                maxLength: 300,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  hintText:
                      'Personality, health conditions, medication, '
                      'allergies...',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String? _intInRange(String? v, int min, int max, String message) {
    if (v == null || v.isEmpty) return null;
    final n = int.tryParse(v);
    return (n == null || n < min || n > max) ? message : null;
  }
}

class _Choice<T extends Object> extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: PetPulzTheme.textDark,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<T>(
              showSelectedIcon: false,
              segments: [
                for (final e in options.entries)
                  ButtonSegment(value: e.key, label: Text(e.value)),
              ],
              selected: {value},
              onSelectionChanged: (s) => onChanged(s.first),
              style: ButtonStyle(
                backgroundColor: MaterialStateProperty.resolveWith((states) {
                  if (states.contains(MaterialState.selected)) {
                    return PetPulzTheme.primaryPurple;
                  }
                  return Colors.white;
                }),
                foregroundColor: MaterialStateProperty.resolveWith((states) {
                  if (states.contains(MaterialState.selected)) {
                    return Colors.white;
                  }
                  return PetPulzTheme.textDark;
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return PetPulzCard(
      padding: const EdgeInsets.all(14),
      color: PetPulzTheme.pillBg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.info_outline_rounded, color: PetPulzTheme.primaryPurple),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Saved locally on this phone. Sent securely to the AI service along with your questions so advice fits your pet.',
              style: TextStyle(color: PetPulzTheme.textDark, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
