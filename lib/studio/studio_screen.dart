import 'package:flutter/material.dart';

import 'package:pet_core/pet_core.dart';
import '../screener/photo_picker.dart';
import '../theme/pet_pulz_theme.dart';
import 'photo_enhancer.dart';
import 'studio_controller.dart';

/// The Instagram content studio: pick a photo, get an enhanced crop plus
/// captions and hashtags, then share.
class StudioScreen extends StatefulWidget {
  const StudioScreen({super.key, required this.controller, this.catName});

  final StudioController controller;
  final String? catName;

  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen> {
  StudioController get _c => widget.controller;

  final _note = TextEditingController();
  final _caption = TextEditingController();
  Object? _captionFor;

  @override
  void dispose() {
    _note.dispose();
    _caption.dispose();
    _c.dispose();
    super.dispose();
  }

  void _startOver() {
    _note.clear();
    _caption.clear();
    _captionFor = null;
    _c.reset();
  }

  void _syncCaptionField() {
    final key = _c.suggestion ?? _c.original;
    if (_captionFor == key) return;
    _captionFor = key;
    _caption.text = _c.captionText;
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copy() async {
    final ok = await _c.copyPostText();
    if (mounted) {
      _snack(ok ? 'Caption and hashtags copied' : 'Couldn\'t copy the caption');
    }
  }

  Future<void> _share(BuildContext buttonContext) async {
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;

    final ok = await _c.shareToInstagram(origin: origin);
    if (!mounted) return;
    _snack(
      ok
          ? 'Caption copied. In Instagram, paste it into the caption box.'
          : 'Couldn\'t open the share sheet.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PetPulzTheme.bgGradientTop,
      appBar: AppBar(
        title: const Text('Photo Studio', style: TextStyle(fontWeight: FontWeight.bold, color: PetPulzTheme.textDark)),
      ),
      body: PetPulzBackground(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: _c,
            builder: (context, _) {
              switch (_c.status) {
                case StudioStatus.start:
                  return _buildStart(context);
                case StudioStatus.working:
                  return _Working(name: widget.catName);
                case StudioStatus.ready:
                  _syncCaptionField();
                  return _buildReady(context);
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildStart(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              color: PetPulzTheme.pillBg,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome_rounded, size: 56, color: PetPulzTheme.primaryPurple),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Create Instagram Post',
          textAlign: TextAlign.center,
          style: text.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: PetPulzTheme.textDark,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Pick a photo and I will brighten it, crop it around '
          '${widget.catName ?? 'your pet'}, and generate captions and hashtags.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: PetPulzTheme.textMuted, fontSize: 14),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _c.pickPhoto(PhotoSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Camera'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _c.pickPhoto(PhotoSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Gallery'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _note,
          onChanged: _c.setNote,
          maxLength: 120,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Anything to mention? (optional)',
            hintText: 'e.g. First snow day, or Birthday nap',
          ),
        ),
        if (_c.error != null) ...[
          const SizedBox(height: 8),
          _Banner(text: _c.error!, kind: _BannerKind.error),
        ],
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.lock_outline_rounded, size: 16, color: PetPulzTheme.textMuted),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                'The photo is processed by the AI service to suggest captions. The app does not save it remotely.',
                style: TextStyle(fontSize: 12, color: PetPulzTheme.textMuted),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReady(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final s = _c.suggestion;
    final image = _c.currentImage!;

    return ListView(
      padding: const EdgeInsets.all(16),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 460),
            child: Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.memory(
                    image,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stack) => const SizedBox(
                      height: 200,
                      child: Center(
                        child: Icon(Icons.broken_image_outlined, size: 48),
                      ),
                    ),
                  ),
                ),
                if (_c.isEnhancing) const CircularProgressIndicator(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_c.enhanced != null)
          Center(
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.auto_fix_high_rounded, size: 18),
                  label: Text('Enhanced'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.image_outlined, size: 18),
                  label: Text('Original'),
                ),
              ],
              selected: {_c.useOriginal},
              onSelectionChanged: (v) => _c.setUseOriginal(v.first),
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
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final a in StudioAspect.values)
              ChoiceChip(
                label: Text(a.label),
                selected: _c.aspect == a,
                onSelected: (_) => _c.setAspect(a),
                selectedColor: PetPulzTheme.primaryPurple,
                labelStyle: TextStyle(
                  color: _c.aspect == a ? Colors.white : PetPulzTheme.textDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        if (_c.warning != null) ...[
          const SizedBox(height: 12),
          _Banner(text: _c.warning!, kind: _BannerKind.warning),
          if (s == null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _c.retry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try captions again'),
              ),
            ),
        ],

        if (s != null) ...[
          const SizedBox(height: 16),
          _MoodCard(mood: s.mood, subject: s.subject),
        ],

        if (s != null && s.captions.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Pick a caption',
            style: text.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: PetPulzTheme.textDark,
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < s.captions.length; i++)
            _CaptionCard(
              option: s.captions[i],
              selected: _c.captionIndex == i,
              onTap: () {
                _c.selectCaption(i);
                _caption.text = _c.captionText;
              },
            ),
        ],
        if (s != null) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _caption,
            onChanged: _c.setCaptionText,
            minLines: 2,
            maxLines: 6,
            maxLength: instagramMaxCaptionLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Your caption (edit freely)',
            ),
          ),
        ],

        if (s != null && s.hashtags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Hashtags',
                style: text.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: PetPulzTheme.textDark,
                ),
              ),
              const Spacer(),
              Text(
                '${_c.selectedTagCount}/$instagramMaxHashtags',
                style: const TextStyle(fontSize: 12, color: PetPulzTheme.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Tap to remove or add back.',
            style: TextStyle(fontSize: 12, color: PetPulzTheme.textMuted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 0,
            children: [
              for (final tag in s.hashtags)
                FilterChip(
                  label: Text('#$tag'),
                  selected: _c.isTagSelected(tag),
                  onSelected: (_) => _c.toggleTag(tag),
                  selectedColor: PetPulzTheme.primaryPurple,
                  labelStyle: TextStyle(
                    color: _c.isTagSelected(tag) ? Colors.white : PetPulzTheme.textDark,
                  ),
                ),
            ],
          ),
        ],

        const SizedBox(height: 20),
        Builder(
          builder: (buttonContext) => FilledButton.icon(
            onPressed: _c.canShare && !_c.isEnhancing
                ? () => _share(buttonContext)
                : null,
            icon: const Icon(Icons.ios_share_rounded),
            label: const Text('Share to Instagram'),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _c.postText.isEmpty ? null : _copy,
          icon: const Icon(Icons.copy_rounded),
          label: const Text('Copy caption & hashtags'),
        ),
        const SizedBox(height: 8),
        const Text(
          'Instagram does not accept a caption from other apps. So the '
          'caption is copied for you: choose Instagram in the share sheet, '
          'then paste it.',
          style: TextStyle(fontSize: 12, color: PetPulzTheme.textMuted),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _startOver,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Start with a new photo'),
        ),
      ],
    );
  }
}

class _Working extends StatelessWidget {
  const _Working({this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: PetPulzTheme.primaryPurple),
            const SizedBox(height: 20),
            Text(
              name == null
                  ? 'Getting your photo ready...'
                  : 'Getting $name\'s photo ready...',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: PetPulzTheme.textDark,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Writing captions and touching up the photo.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: PetPulzTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoodCard extends StatelessWidget {
  const _MoodCard({required this.mood, required this.subject});

  final PetMood mood;
  final String subject;

  @override
  Widget build(BuildContext context) {
    return PetPulzCard(
      padding: const EdgeInsets.all(14),
      color: PetPulzTheme.pillBg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(mood.emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mood: ${mood.label}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: PetPulzTheme.primaryPurple,
                  ),
                ),
                if (subject.isNotEmpty)
                  Text(
                    subject,
                    style: const TextStyle(color: PetPulzTheme.textDark),
                  ),
                const SizedBox(height: 4),
                Text(
                  'Sound vibe for a future Reel: ${mood.soundVibe}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: PetPulzTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CaptionCard extends StatelessWidget {
  const _CaptionCard({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final CaptionOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: PetPulzCard(
        margin: const EdgeInsets.only(bottom: 8),
        color: selected ? PetPulzTheme.pillBg : Colors.white,
        padding: const EdgeInsets.all(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? PetPulzTheme.primaryPurple : PetPulzTheme.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (option.tone.isNotEmpty)
                      Text(
                        option.tone.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: selected ? PetPulzTheme.primaryPurple : PetPulzTheme.textMuted,
                          letterSpacing: 1,
                        ),
                      ),
                    Text(
                      option.text,
                      style: const TextStyle(color: PetPulzTheme.textDark),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _BannerKind { error, warning }

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.kind});

  final String text;
  final _BannerKind kind;

  @override
  Widget build(BuildContext context) {
    final error = kind == _BannerKind.error;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: error ? const Color(0xFFFFEBEB) : PetPulzTheme.pillBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: error ? Colors.redAccent : PetPulzTheme.primaryPurple,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
