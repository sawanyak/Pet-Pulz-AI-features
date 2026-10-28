import 'package:flutter/material.dart';

import 'package:pet_core/pet_core.dart';
import '../theme/pet_pulz_theme.dart';
import 'photo_picker.dart';
import 'screener_controller.dart';

/// The photo health check: pick photos -> describe -> analyze -> result.
class HealthScreenerScreen extends StatefulWidget {
  const HealthScreenerScreen({super.key, required this.controller});

  final ScreenerController controller;

  @override
  State<HealthScreenerScreen> createState() => _HealthScreenerScreenState();
}

class _HealthScreenerScreenState extends State<HealthScreenerScreen> {
  ScreenerController get _c => widget.controller;
  final _concern = TextEditingController();

  @override
  void dispose() {
    _concern.dispose();
    _c.dispose();
    super.dispose();
  }

  void _startOver() {
    _concern.clear();
    _c.reset();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PetPulzTheme.bgGradientTop,
      appBar: AppBar(
        title: const Text('Photo Health Check', style: TextStyle(fontWeight: FontWeight.bold, color: PetPulzTheme.textDark)),
      ),
      body: PetPulzBackground(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: _c,
            builder: (context, _) => switch (_c.status) {
              ScreenerStatus.input => _buildInput(context),
              ScreenerStatus.analyzing => const _Analyzing(),
              ScreenerStatus.result => _ResultView(
                screening: _c.result!,
                onNewCheck: _startOver,
              ),
            },
          ),
        ),
      ),
    );
  }

  Widget _buildInput(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        const _DisclaimerCard(),
        const SizedBox(height: 16),
        Text(
          '1. Add photos',
          style: text.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: PetPulzTheme.textDark,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Good daylight, in focus, close to the area. Add a wider shot if '
          'it is about how she moves or stands. Up to '
          '${ScreenerController.maxPhotos} photos.',
          style: TextStyle(fontSize: 12, color: PetPulzTheme.textMuted),
        ),
        const SizedBox(height: 12),
        if (_c.photos.isNotEmpty)
          SizedBox(
            height: 104,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _c.photos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final photo = _c.photos[i];
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.memory(
                        photo.bytes,
                        width: 104,
                        height: 104,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: InkWell(
                        onTap: () => _c.removePhoto(i),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(4),
                          child: const Icon(Icons.close, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        if (_c.photos.isNotEmpty) const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _c.canAddPhoto
                    ? () => _c.addPhoto(PhotoSource.camera)
                    : null,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Camera'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _c.canAddPhoto
                    ? () => _c.addPhoto(PhotoSource.gallery)
                    : null,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Gallery'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          '2. Tell us what you noticed',
          style: text.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: PetPulzTheme.textDark,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _concern,
          onChanged: _c.setConcern,
          minLines: 2,
          maxLines: 4,
          maxLength: 240,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'What are you concerned about?',
            hintText: 'e.g. Redness on left ear, scratching for 2 days',
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '3. How long has this been going on?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: PetPulzTheme.textDark,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final d in ConcernDuration.values)
              ChoiceChip(
                label: Text(d.label),
                selected: _c.duration == d,
                onSelected: (selected) =>
                    _c.setDuration(selected ? d : null),
                selectedColor: PetPulzTheme.primaryPurple,
                labelStyle: TextStyle(
                  color: _c.duration == d ? Colors.white : PetPulzTheme.textDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        if (_c.error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEBEB),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _c.error!,
                  style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _c.analyze,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _c.canAnalyze ? _c.analyze : null,
          icon: const Icon(Icons.analytics_outlined),
          label: const Text('Check photos'),
        ),
      ],
    );
  }
}

class _Analyzing extends StatelessWidget {
  const _Analyzing();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            CircularProgressIndicator(color: PetPulzTheme.primaryPurple),
            SizedBox(height: 20),
            Text(
              'Analyzing photos...',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: PetPulzTheme.textDark,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Checking for visible signs and urgency.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: PetPulzTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.screening, required this.onNewCheck});

  final HealthScreening screening;
  final VoidCallback onNewCheck;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _DisclaimerCard(),
        const SizedBox(height: 16),
        _UrgencyBadge(urgency: screening.urgency),
        if (screening.photoNote != null) ...[
          const SizedBox(height: 8),
          _SignBanner(
            text: screening.photoNote!,
            icon: Icons.camera_alt_rounded,
            emphasis: false,
          ),
        ],
        if (screening.escalationReason != null) ...[
          const SizedBox(height: 8),
          _SignBanner(
            text: screening.escalationReason!,
            icon: Icons.info_outline_rounded,
            emphasis: true,
          ),
        ],
        const SizedBox(height: 12),
        PetPulzCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Summary',
                style: text.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: PetPulzTheme.textDark,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                screening.summary,
                style: const TextStyle(color: PetPulzTheme.textDark, height: 1.4),
              ),
            ],
          ),
        ),
        if (screening.observations.isNotEmpty) ...[
          const SizedBox(height: 12),
          PetPulzCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Observations',
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: PetPulzTheme.textDark,
                  ),
                ),
                const SizedBox(height: 6),
                for (final obs in screening.observations)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• ', style: TextStyle(fontWeight: FontWeight.bold, color: PetPulzTheme.primaryPurple)),
                        Expanded(child: Text(obs, style: const TextStyle(color: PetPulzTheme.textDark))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (screening.possibleCauses.isNotEmpty) ...[
          const SizedBox(height: 12),
          PetPulzCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Possible Causes',
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: PetPulzTheme.textDark,
                  ),
                ),
                const SizedBox(height: 6),
                for (final cause in screening.possibleCauses)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• ', style: TextStyle(fontWeight: FontWeight.bold, color: PetPulzTheme.primaryPurple)),
                        Expanded(child: Text(cause, style: const TextStyle(color: PetPulzTheme.textDark))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (screening.seeVetIf.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionTitle(
            title: 'Warning signs',
            subtitle: 'See a vet if you notice any of these',
            icon: Icons.warning_amber_rounded,
            color: Theme.of(context).colorScheme.error,
          ),
          for (final sign in screening.seeVetIf)
            _SignBanner(text: sign, icon: Icons.warning_amber_rounded, emphasis: true),
        ],
        if (screening.homeCare.isNotEmpty) ...[
          const SizedBox(height: 24),
          const _SectionTitle(
            title: 'Things to do',
            subtitle: 'Simple care you can do at home',
            icon: Icons.check_circle_outline_rounded,
            color: PetPulzTheme.primaryPurple,
          ),
          for (final r in screening.homeCare)
            _SignBanner(text: r, icon: Icons.check_circle_outline_rounded, emphasis: false),
        ],
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: onNewCheck,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Start another check'),
        ),
      ],
    );
  }
}

/// A heading that starts a group of banners (e.g. "Warning signs").
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 13, color: PetPulzTheme.textMuted),
          ),
        ],
      ),
    );
  }
}

class _UrgencyBadge extends StatelessWidget {
  const _UrgencyBadge({required this.urgency});

  final Urgency urgency;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, IconData icon, String label, String? detail) =
        switch (urgency) {
      Urgency.emergency => (
        Colors.red.shade100,
        Colors.red.shade900,
        Icons.emergency_rounded,
        'Get to a vet now',
        'This looks serious or urgent.',
      ),
      Urgency.seeVetSoon => (
        Colors.orange.shade100,
        Colors.orange.shade900,
        Icons.schedule_rounded,
        'See a vet soon',
        'See a vet within 1-2 days',
      ),
      Urgency.monitorAtHome => (
        PetPulzTheme.pillBg,
        PetPulzTheme.primaryPurple,
        Icons.check_circle_outline_rounded,
        'Keep an eye on her at home',
        'Nothing alarming is visible. Watch for changes.',
      ),
      Urgency.cannotAssess => (
        Colors.grey.shade200,
        Colors.grey.shade800,
        Icons.help_outline_rounded,
        'I can\'t tell from these photos',
        'This does not mean everything is fine. If your cat seems unwell, contact a vet.',
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: fg, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          if (detail != null) ...[
            const SizedBox(height: 4),
            Text(
              detail,
              style: TextStyle(color: fg, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

class _SignBanner extends StatelessWidget {
  const _SignBanner({
    required this.text,
    required this.icon,
    required this.emphasis,
  });

  final String text;
  final IconData icon;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final bg = emphasis ? const Color(0xFFFFEBEB) : PetPulzTheme.pillBg;
    final fg = emphasis ? Colors.redAccent : PetPulzTheme.primaryPurple;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: fg, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _DisclaimerCard extends StatelessWidget {
  const _DisclaimerCard();

  @override
  Widget build(BuildContext context) {
    return PetPulzCard(
      padding: const EdgeInsets.all(12),
      color: Colors.white,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.info_outline_rounded, size: 20, color: PetPulzTheme.textMuted),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              screenerDisclaimer,
              style: TextStyle(fontSize: 12, color: PetPulzTheme.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
