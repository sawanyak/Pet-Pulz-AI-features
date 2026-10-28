import 'package:flutter/material.dart';

import 'package:pet_core/pet_core.dart';
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
import '../voice/voice_controller.dart';
import '../voice/voice_screen.dart';
import '../widgets/message_bubble.dart';
import '../widgets/typing_indicator.dart';
import 'chat_controller.dart';
import 'chat_history.dart';

/// Conversation starters shown on an empty chat. Tapping one sends it.
List<String> _suggestions(String? name) {
  final cat = name ?? 'my cat';
  final subject = name ?? 'My cat';
  return [
    '5 engaging games for ${name ?? 'a lethargic indoor cat'}',
    '$subject has been sneezing a lot. Should I worry?',
    'How do I introduce a new kitten to $cat?',
    'Why does $cat scratch the sofa?',
  ];
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({
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

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  ChatController get _chat => widget.controller;
  CatProfileStore get _profiles => widget.profileStore;

  void _openVoice() {
    _chat.stopReply();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VoiceScreen(
          voice: VoiceController(
            chat: _chat,
            input: widget.speechInput,
            output: widget.speechOutput,
          ),
        ),
      ),
    );
  }

  void _openScreener() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => HealthScreenerScreen(
        controller: ScreenerController(
          service: widget.visionService,
          picker: widget.photoPicker,
          profiles: _profiles,
        ),
      ),
    ),
  );

  void _openStudio() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => StudioScreen(
        catName: _profiles.profile?.name,
        controller: StudioController(
          content: widget.contentService,
          picker: widget.photoPicker,
          enhancer: widget.photoEnhancer,
          share: widget.shareService,
          profiles: _profiles,
        ),
      ),
    ),
  );

  void _openProfile() => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => CatProfileScreen(store: _profiles)),
  );

  @override
  void initState() {
    super.initState();
    _chat.addListener(_scrollToBottom);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _chat.removeListener(_scrollToBottom);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final bottom = _scroll.position.maxScrollExtent;
      if (_chat.isStreaming) {
        _scroll.jumpTo(bottom);
      } else {
        _scroll.animateTo(
          bottom,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _submit([String? text]) {
    _chat.send(text ?? _input.text);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: PetPulzTheme.bgGradientTop,
      drawer: _ChatHistoryDrawer(controller: _chat),
      appBar: PetPulzHeader(
        onBackPressed: () => Navigator.of(context).maybePop(),
        trailing: IconButton(
          tooltip: 'Chat history',
          icon: const Icon(Icons.history_rounded, color: PetPulzTheme.primaryPurple, size: 28),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
      ),
      body: PetPulzBackground(
        child: ListenableBuilder(
          listenable: Listenable.merge([_chat, _profiles]),
          builder: (context, _) => Column(
            children: [
              if (widget.usingMock) const _MockBanner(),
              if (_profiles.profile != null)
                _ProfileChip(profile: _profiles.profile!, onTap: _openProfile),
              Expanded(child: _buildMessages()),
              _buildInputBar(),
            ],
          ),
        ),
      ),
    );

  }

  Widget _buildMessages() {
    final messages = _chat.messages;
    if (messages.isEmpty) return _buildWelcome();

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      itemCount: messages.length + (_chat.isThinking ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == messages.length) return const TypingIndicator();
        final m = messages[i];
        return MessageBubble(
          message: m,
          onRetry: m.isError && i == messages.length - 1 ? _chat.retry : null,
        );
      },
    );
  }

  Widget _buildWelcome() {
    final cat = _profiles.profile;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        PetPulzCard(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFE5DAFC),
              Color(0xFFF2EAFA),
              Color(0xFFEBF1FD),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PetPulzPillBadge(
                text: 'THE ULTIMATE SANCTUARY',
                icon: Icons.auto_awesome_rounded,
              ),
              const SizedBox(height: 10),
              Text(
                cat == null ? 'Hi, I\'m Whiskers!' : 'Hi! How is ${cat.name} today?',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: PetPulzTheme.primaryPurple,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'A comprehensive care platform designed with empathy.',
                style: TextStyle(
                  fontSize: 13,
                  color: PetPulzTheme.textMuted,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        if (cat == null) ...[
          FilledButton.tonalIcon(
            onPressed: _openProfile,
            icon: const Icon(Icons.pets),
            label: const Text('Add your cat\'s profile'),
          ),
          const SizedBox(height: 4),
          Text(
            'Get advice that fits your cat\'s age, breed and health.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
        ],

        OutlinedButton.icon(
          onPressed: _openScreener,
          icon: const Icon(Icons.health_and_safety_outlined),
          label: const Text('Photo health check'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _openStudio,
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const Text('Photo studio for Instagram'),
        ),
        const SizedBox(height: 12),
        for (final s in _suggestions(cat?.name))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton(
              onPressed: () => _submit(s),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(s, textAlign: TextAlign.center),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x124A3BB5),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _submit,
                  decoration: const InputDecoration(
                    hintText: 'Ask Pet Pulz AI...',
                    filled: false,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: const BoxDecoration(
                color: PetPulzTheme.pillBg,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                tooltip: 'Voice mode',
                onPressed: _openVoice,
                icon: const Icon(Icons.mic_rounded, color: PetPulzTheme.primaryPurple),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              decoration: const BoxDecoration(
                color: PetPulzTheme.primaryPurple,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                tooltip: _chat.isBusy ? 'Stop' : 'Send',
                onPressed: _chat.isBusy ? _chat.stopReply : () => _submit(),
                icon: Icon(
                  _chat.isBusy ? Icons.stop_rounded : Icons.send_rounded,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MockBanner extends StatelessWidget {
  const _MockBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: PetPulzTheme.pillBg,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: const Text(
        'Demo mode: no API key set, replies are fake.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: PetPulzTheme.primaryPurple,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ProfileChip extends StatelessWidget {
  const _ProfileChip({required this.profile, required this.onTap});

  final CatProfile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final details = [
      profile.name,
      if (profile.hasAge) profile.ageLabel,
      if (profile.breed.isNotEmpty) profile.breed,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFDDD5FB)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.pets_rounded, size: 16, color: PetPulzTheme.primaryPurple),
                const SizedBox(width: 8),
                Text(
                  details,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: PetPulzTheme.textDark,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, size: 18, color: PetPulzTheme.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The left-hand panel: every saved chat, a "New chat" button and a delete
/// button beside each chat.
class _ChatHistoryDrawer extends StatelessWidget {
  const _ChatHistoryDrawer({required this.controller});

  final ChatController controller;

  Future<void> _confirmDelete(BuildContext context, ChatSession s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this chat?'),
        content: Text('"${s.title}" will be removed for good.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) controller.deleteChat(s.id);
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: PetPulzTheme.bgGradientTop,
      child: SafeArea(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final sessions = controller.sessions;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text(
                    'Chats',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: PetPulzTheme.primaryPurple,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        controller.newChat();
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('New chat'),
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: sessions.length,
                    itemBuilder: (context, i) {
                      final s = sessions[i];
                      final selected = s.id == controller.activeChatId;
                      return ListTile(
                        selected: selected,
                        selectedTileColor: PetPulzTheme.activeNavHighlight,
                        leading: const Icon(Icons.chat_bubble_outline_rounded),
                        title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () {
                          controller.selectChat(s.id);
                          Navigator.of(context).pop();
                        },
                        trailing: IconButton(
                          tooltip: 'Delete chat',
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () => _confirmDelete(context, s),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
