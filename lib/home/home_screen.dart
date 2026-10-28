import 'package:flutter/material.dart';

import 'package:pet_core/pet_core.dart';
import '../chat/chat_controller.dart';
import '../chat/chat_screen.dart';
import '../profile/cat_profile_screen.dart';
import '../profile/cat_profile_store.dart';
import '../screener/health_screener_screen.dart';
import '../screener/photo_picker.dart';
import '../screener/screener_controller.dart';
import '../studio/photo_enhancer.dart';
import '../studio/share_service.dart';
import '../studio/studio_controller.dart';
import '../studio/studio_screen.dart';
import '../theme/pet_pulz_theme.dart';
import '../voice/speech_io.dart';

/// The app's landing page. Shows a greeting, shortcuts to every feature and a
/// chat button that opens the AI chat. Only wires existing screens together.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    required this.profileStore,
    required this.speechInput,
    required this.speechOutput,
    required this.visionService,
    required this.photoPicker,
    required this.contentService,
    required this.photoEnhancer,
    required this.shareService,
    this.usingMock = false,
  });

  final ChatController controller;
  final CatProfileStore profileStore;
  final SpeechInput speechInput;
  final SpeechOutput speechOutput;
  final VisionService visionService;
  final PhotoPicker photoPicker;
  final ContentService contentService;
  final PhotoEnhancer photoEnhancer;
  final ShareService shareService;
  final bool usingMock;

  void _openChat(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatScreen(
            controller: controller,
            profileStore: profileStore,
            speechInput: speechInput,
            speechOutput: speechOutput,
            visionService: visionService,
            photoPicker: photoPicker,
            contentService: contentService,
            photoEnhancer: photoEnhancer,
            shareService: shareService,
            usingMock: usingMock,
          ),
        ),
      );

  void _openScreener(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => HealthScreenerScreen(
            controller: ScreenerController(
              service: visionService,
              picker: photoPicker,
              profiles: profileStore,
            ),
          ),
        ),
      );

  void _openStudio(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => StudioScreen(
            catName: profileStore.profile?.name,
            controller: StudioController(
              content: contentService,
              picker: photoPicker,
              enhancer: photoEnhancer,
              share: shareService,
              profiles: profileStore,
            ),
          ),
        ),
      );

  void _openProfile(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CatProfileScreen(store: profileStore),
        ),
      );

  void _handleNavTap(BuildContext context, int index) {
    switch (index) {
      case 1:
        _openScreener(context);
      case 2:
        _openStudio(context);
      case 3:
        _openProfile(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PetPulzTheme.bgGradientTop,
      appBar: const PetPulzHeader(),
      body: PetPulzBackground(
        child: ListenableBuilder(
          listenable: profileStore,
          builder: (context, _) => _buildBody(context),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Chat with Pet Pulz AI',
        backgroundColor: PetPulzTheme.primaryPurple,
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
        onPressed: () => _openChat(context),
        child: const Icon(Icons.chat_bubble_rounded),
      ),
      bottomNavigationBar: PetPulzBottomNav(
        currentIndex: 0,
        onTap: (i) => _handleNavTap(context, i),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final cat = profileStore.profile;
    final name = cat?.name;
    final subtitle = cat == null
        ? 'Add your cat\'s profile to get advice that fits.'
        : [
            if (cat.hasAge) cat.ageLabel,
            if (cat.breed.isNotEmpty) cat.breed,
          ].join(' · ');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        PetPulzCard(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE5DAFC), Color(0xFFF2EAFA), Color(0xFFEBF1FD)],
          ),
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const PetPulzPillBadge(
                      text: 'The ultimate sanctuary',
                      icon: Icons.auto_awesome_rounded,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      name == null ? 'Welcome to PetPulz' : 'Hi! How is $name today?',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: PetPulzTheme.primaryPurple,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle.isEmpty
                          ? 'A comprehensive care platform designed with empathy.'
                          : subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: PetPulzTheme.textMuted,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.pets_rounded, size: 32, color: PetPulzTheme.primaryPurple),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _ChatPromptCard(onTap: () => _openChat(context)),
        const SizedBox(height: 20),
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'Quick actions',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: PetPulzTheme.textDark,
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _ActionTile(
                icon: Icons.auto_awesome_outlined,
                title: 'Photo studio',
                subtitle: 'Captions & Instagram',
                onTap: () => _openStudio(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionTile(
                icon: Icons.health_and_safety_outlined,
                title: 'Health check',
                subtitle: 'Analyse a photo',
                onTap: () => _openScreener(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ActionTile(
                icon: Icons.pets_rounded,
                title: 'My pets',
                subtitle: cat == null ? 'Add a profile' : 'View ${cat.name}\'s profile',
                onTap: () => _openProfile(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionTile(
                icon: Icons.chat_bubble_outline_rounded,
                title: 'Ask AI',
                subtitle: 'Care advice 24/7',
                onTap: () => _openChat(context),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ChatPromptCard extends StatelessWidget {
  const _ChatPromptCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: PetPulzCard(
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: PetPulzTheme.pillBg,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.chat_bubble_rounded, color: PetPulzTheme.primaryPurple),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ask Pet Pulz AI',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: PetPulzTheme.textDark,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Chat about health, food, behaviour and more.',
                    style: TextStyle(fontSize: 12, color: PetPulzTheme.textMuted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: PetPulzTheme.textMuted),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: PetPulzCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: PetPulzTheme.pillBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: PetPulzTheme.primaryPurple, size: 24),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: PetPulzTheme.textDark,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: PetPulzTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
