import 'package:flutter/foundation.dart';

import 'package:pet_core/pet_core.dart';
import '../profile/cat_profile_store.dart';
import 'photo_picker.dart';

enum ScreenerStatus {
  /// Choosing photos and describing the problem.
  input,

  /// Waiting for the AI.
  analyzing,

  /// Showing the result.
  result,
}

/// "How long has this been going on?" chips.
enum ConcernDuration {
  justNoticed('Just noticed'),
  fewDays('A few days'),
  weekOrMore('A week or more');

  const ConcernDuration(this.label);
  final String label;
}

/// State and logic of the photo health check. The screen only draws it.
class ScreenerController extends ChangeNotifier {
  ScreenerController({
    required this.service,
    required this.picker,
    required this.profiles,
  });

  final VisionService service;
  final PhotoPicker picker;
  final CatProfileStore profiles;

  /// Two or three angles help (a close-up plus a wider shot), more is slow.
  static const maxPhotos = 3;

  final List<ScreenerPhoto> _photos = [];
  String _concern = '';
  ConcernDuration? _duration;
  ScreenerStatus _status = ScreenerStatus.input;
  HealthScreening? _result;
  String? _error;
  bool _disposed = false;
  int _run = 0; // bumped by reset() so a late answer is ignored

  List<ScreenerPhoto> get photos => List.unmodifiable(_photos);
  String get concern => _concern;
  ConcernDuration? get duration => _duration;
  ScreenerStatus get status => _status;
  HealthScreening? get result => _result;

  /// A message to show above the form (a failed pick or a failed analysis).
  String? get error => _error;

  bool get canAddPhoto =>
      _photos.length < maxPhotos && _status == ScreenerStatus.input;
  bool get canAnalyze => _photos.isNotEmpty && _status == ScreenerStatus.input;

  Future<void> addPhoto(PhotoSource source) async {
    if (!canAddPhoto) return;
    _error = null;
    try {
      final photo = await picker.pick(source);
      if (photo != null && !_disposed && _photos.length < maxPhotos) {
        _photos.add(photo);
      }
    } on PhotoPickerException catch (e) {
      _error = e.message;
    }
    _notify();
  }

  void removePhoto(int index) {
    if (_status != ScreenerStatus.input) return;
    if (index < 0 || index >= _photos.length) return;
    _photos.removeAt(index);
    _notify();
  }

  void setConcern(String text) {
    // No notify: the text field owns the text; we only remember it.
    _concern = text;
  }

  void setDuration(ConcernDuration? d) {
    _duration = d;
    _notify();
  }

  Future<void> analyze() async {
    if (!canAnalyze) return;
    final run = ++_run;
    _error = null;
    _status = ScreenerStatus.analyzing;
    _notify();

    try {
      final raw = await service.screen(
        photos: List.of(_photos),
        concern: _concern,
        duration: _duration?.label,
        cat: profiles.profile,
      );
      if (run != _run) return; // the person started over meanwhile

      // Safety net: the owner's own words can raise, never lower, urgency.
      _result = applySafetyFloor(_concern, raw);
      _status = ScreenerStatus.result;
    } on AiServiceException catch (e) {
      if (run != _run) return;
      _error = e.message;
      _status = ScreenerStatus.input; // keep the photos so they can retry
    } catch (_) {
      if (run != _run) return;
      _error = 'Something unexpected went wrong. Please try again.';
      _status = ScreenerStatus.input;
    }
    _notify();
  }

  /// Start a fresh check (clears photos and text).
  void reset() {
    _run++;
    _photos.clear();
    _concern = '';
    _duration = null;
    _result = null;
    _error = null;
    _status = ScreenerStatus.input;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _run++;
    super.dispose();
  }
}
