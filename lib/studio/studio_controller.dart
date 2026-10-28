import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'package:pet_core/pet_core.dart';
import '../profile/cat_profile_store.dart';
import '../screener/photo_picker.dart';
import 'photo_enhancer.dart';
import 'share_service.dart';

enum StudioStatus {
  /// Choosing a photo.
  start,

  /// Writing captions and enhancing.
  working,

  /// Showing the finished post.
  ready,
}

/// State and logic of the content studio:
///   pick a photo -> AI suggests mood/focus/captions/hashtags
///   -> enhance + crop around the pet -> choose & edit -> share.
class StudioController extends ChangeNotifier {
  StudioController({
    required this.content,
    required this.picker,
    required this.enhancer,
    required this.share,
    required this.profiles,
  });

  final ContentService content;
  final PhotoPicker picker;
  final PhotoEnhancer enhancer;
  final ShareService share;
  final CatProfileStore profiles;

  /// Long side in pixels of the photo we work from. Bigger than the health
  /// check uses, so the crop stays sharp at Instagram's 1080 px.
  static const workingSize = 2048;

  StudioStatus _status = StudioStatus.start;
  ScreenerPhoto? _original;
  Uint8List? _enhanced;
  ContentSuggestion? _suggestion;

  String _note = '';
  StudioAspect _aspect = StudioAspect.portrait;
  bool _useOriginal = false;
  bool _enhancing = false; // re-cropping after the shape changed

  int _captionIndex = 0;
  String _captionText = '';
  final Set<String> _selectedTags = {};

  String? _error; // shown on the start screen
  String? _warning; // shown on the result (something partly failed)

  bool _disposed = false;
  int _run = 0; // bumped when the whole process restarts
  int _enhanceRun = 0; // bumped for every (re-)enhance

  // ------------------------------------------------------------- read state

  StudioStatus get status => _status;
  ScreenerPhoto? get original => _original;
  Uint8List? get enhanced => _enhanced;
  ContentSuggestion? get suggestion => _suggestion;
  String get note => _note;
  StudioAspect get aspect => _aspect;
  bool get useOriginal => _useOriginal;
  bool get isEnhancing => _enhancing;
  int get captionIndex => _captionIndex;
  String get captionText => _captionText;
  String? get error => _error;
  String? get warning => _warning;

  /// The picture that will be posted.
  Uint8List? get currentImage =>
      _useOriginal ? _original?.bytes : (_enhanced ?? _original?.bytes);

  bool isTagSelected(String tag) => _selectedTags.contains(tag);
  int get selectedTagCount => _selectedTags.length;

  /// Selected hashtags, in the AI's original order.
  List<String> get selectedTags => [
    for (final t in _suggestion?.hashtags ?? const <String>[])
      if (_selectedTags.contains(t)) t,
  ];

  /// The exact text that gets copied for Instagram.
  String get postText => composePost(_captionText, selectedTags);

  bool get canShare => currentImage != null && _status == StudioStatus.ready;

  // ------------------------------------------------------------------ input

  void setNote(String text) => _note = text; // the field owns the text

  Future<void> pickPhoto(PhotoSource source) async {
    if (_status == StudioStatus.working) return;
    _error = null;
    try {
      final photo = await picker.pick(source, maxDimension: workingSize);
      if (photo == null || _disposed) return;
      _original = photo;
    } on PhotoPickerException catch (e) {
      _error = e.message;
      _notify();
      return;
    }
    await _process();
  }

  /// Runs the whole pipeline. Also used to retry after a captions failure.
  Future<void> _process() async {
    final photo = _original;
    if (photo == null) return;
    final run = ++_run;
    _status = StudioStatus.working;
    _error = null;
    _warning = null;
    _suggestion = null;
    _enhanced = null;
    _useOriginal = false;
    _notify();

    // 1. Captions first: the AI also tells us where the pet's face is, which
    //    the crop needs.
    ContentSuggestion? suggestion;
    try {
      suggestion = await content.suggest(
        photo: photo,
        note: _note,
        cat: profiles.profile,
      );
    } on AiServiceException catch (e) {
      _warning = 'I couldn\'t write captions: ${e.message}';
    } catch (_) {
      _warning = 'I couldn\'t write captions this time.';
    }
    if (run != _run) return; // the person started over meanwhile

    // 2. Enhance + crop (works even if the captions failed: centred crop).
    final enhanceRun = ++_enhanceRun;
    Uint8List? enhanced;
    try {
      enhanced = await enhancer.enhance(
        photo.bytes,
        focusX: suggestion?.focusX ?? 0.5,
        focusY: suggestion?.focusY ?? 0.5,
        aspect: _aspect,
      );
    } catch (e) {
      // Enhancing failed: fall back to the untouched photo.
      _warning =
          '${_warning == null ? '' : '$_warning '}'
          'I couldn\'t enhance this photo, so this is the original.';
      _useOriginal = true;
    }
    if (run != _run || enhanceRun != _enhanceRun) return;

    _suggestion = suggestion;
    _enhanced = enhanced;
    _captionIndex = 0;
    _captionText = (suggestion != null && suggestion.captions.isNotEmpty)
        ? suggestion.captions.first.text
        : '';
    _selectedTags
      ..clear()
      ..addAll(suggestion?.hashtags ?? const <String>[]);
    _status = StudioStatus.ready;
    _notify();
  }

  /// Try again after captions failed (keeps the chosen photo).
  Future<void> retry() async {
    if (_status != StudioStatus.ready || _original == null) return;
    await _process();
  }

  // ---------------------------------------------------------------- editing

  /// Change the post shape; only the local crop is redone (no AI call).
  Future<void> setAspect(StudioAspect aspect) async {
    if (aspect == _aspect || _status != StudioStatus.ready) return;
    final photo = _original;
    if (photo == null) return;
    _aspect = aspect;
    _enhancing = true;
    final run = ++_enhanceRun;
    _notify();

    try {
      final bytes = await enhancer.enhance(
        photo.bytes,
        focusX: _suggestion?.focusX ?? 0.5,
        focusY: _suggestion?.focusY ?? 0.5,
        aspect: aspect,
      );
      if (run != _enhanceRun || _disposed) return;
      _enhanced = bytes;
    } catch (_) {
      if (run != _enhanceRun) return;
      _warning = 'I couldn\'t re-crop the photo.';
    }
    _enhancing = false;
    _notify();
  }

  void setUseOriginal(bool value) {
    if (_useOriginal == value) return;
    _useOriginal = value;
    _notify();
  }

  void selectCaption(int index) {
    final captions = _suggestion?.captions ?? const [];
    if (index < 0 || index >= captions.length) return;
    _captionIndex = index;
    _captionText = captions[index].text;
    _notify();
  }

  /// The owner edited the caption by hand.
  void setCaptionText(String text) {
    _captionText = text;
    _notify();
  }

  void toggleTag(String tag) {
    if (!_selectedTags.remove(tag)) _selectedTags.add(tag);
    _notify();
  }

  // ---------------------------------------------------------------- sharing

  Future<bool> copyPostText() async {
    try {
      await share.copyText(postText);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Copies the caption FIRST (Instagram ignores text sent through the share
  /// sheet, so the owner pastes it), then opens the share sheet with the
  /// photo. Returns false if something failed.
  Future<bool> shareToInstagram({Rect? origin}) async {
    final image = currentImage;
    if (image == null) return false;
    try {
      await share.copyText(postText);
      await share.shareImage(image, text: postText, origin: origin);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Start over with a new photo.
  void reset() {
    _run++;
    _enhanceRun++;
    _original = null;
    _enhanced = null;
    _suggestion = null;
    _note = '';
    _aspect = StudioAspect.portrait;
    _useOriginal = false;
    _enhancing = false;
    _captionIndex = 0;
    _captionText = '';
    _selectedTags.clear();
    _error = null;
    _warning = null;
    _status = StudioStatus.start;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _run++;
    _enhanceRun++;
    super.dispose();
  }
}
