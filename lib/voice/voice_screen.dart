import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import 'package:pet_core/pet_core.dart';
import '../theme/pet_pulz_theme.dart';
import 'voice_controller.dart';

/// Full-screen hands-free mode: a big orb that shows what the assistant is
/// doing, the live transcript of what you say, and the latest answer.
class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key, required this.voice});

  final VoiceController voice;

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen>
    with SingleTickerProviderStateMixin {
  VoiceController get _voice => widget.voice;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _voice.start());
  }

  @override
  void dispose() {
    _pulse.dispose();
    _voice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PetPulzTheme.bgGradientTop,
      appBar: AppBar(
        title: const Text('Voice Mode', style: TextStyle(fontWeight: FontWeight.bold, color: PetPulzTheme.textDark)),
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded, color: PetPulzTheme.primaryPurple),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: PetPulzBackground(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: Listenable.merge([_voice, _voice.chat]),
            builder: (context, _) => Column(
              children: [
                const SizedBox(height: 24),
                _Orb(state: _voice.state, pulse: _pulse, onTap: _voice.onOrbTap),
                const SizedBox(height: 24),
                Text(
                  _label(_voice.state),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: PetPulzTheme.primaryPurple,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _hint(_voice.state),
                  style: const TextStyle(color: PetPulzTheme.textMuted, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                if (_voice.notice != null) _Notice(text: _voice.notice!),
                const SizedBox(height: 16),
                Expanded(child: _Conversation(voice: _voice)),
                if (_voice.isActive)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: OutlinedButton.icon(
                      onPressed: _voice.stop,
                      icon: const Icon(Icons.pause_circle_outline_rounded),
                      label: const Text('Pause Voice Mode'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _label(VoiceState s) => switch (s) {
    VoiceState.idle => 'Tap to talk',
    VoiceState.listening => 'Listening...',
    VoiceState.thinking => 'Thinking...',
    VoiceState.speaking => 'Speaking...',
  };

  static String _hint(VoiceState s) => switch (s) {
    VoiceState.idle => 'Ask Pet Pulz AI anything about your pet',
    VoiceState.listening => 'Just speak naturally. Tap the orb when done.',
    VoiceState.thinking => 'Tap the orb to cancel and ask again',
    VoiceState.speaking => 'Tap the orb to interrupt',
  };
}

class _Orb extends StatelessWidget {
  const _Orb({required this.state, required this.pulse, required this.onTap});

  final VoiceState state;
  final Animation<double> pulse;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (Color color, Color onColor, IconData icon) = switch (state) {
      VoiceState.idle => (
        PetPulzTheme.pillBg,
        PetPulzTheme.primaryPurple,
        Icons.mic_none_rounded,
      ),
      VoiceState.listening => (
        PetPulzTheme.primaryPurple,
        Colors.white,
        Icons.mic_rounded,
      ),
      VoiceState.thinking => (
        const Color(0xFF8B5CF6),
        Colors.white,
        Icons.more_horiz_rounded,
      ),
      VoiceState.speaking => (
        PetPulzTheme.primaryPurple,
        Colors.white,
        Icons.volume_up_rounded,
      ),
    };
    final breathes =
        state == VoiceState.listening || state == VoiceState.speaking;

    return Semantics(
      button: true,
      label: 'Voice assistant, ${state.name}',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedBuilder(
          animation: pulse,
          builder: (context, child) {
            final scale = breathes ? 1.0 + 0.08 * pulse.value : 1.0;
            return Transform.scale(scale: scale, child: child);
          },
          child: Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: PetPulzTheme.primaryPurple.withOpacity(state != VoiceState.idle ? 0.4 : 0.15),
                  blurRadius: 30,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: Icon(icon, size: 64, color: onColor),
          ),
        ),
      ),
    );
  }
}

class _Conversation extends StatelessWidget {
  const _Conversation({required this.voice});

  final VoiceController voice;

  @override
  Widget build(BuildContext context) {
    final messages = voice.chat.messages;

    final youSaid = voice.state == VoiceState.listening
        ? voice.transcript
        : messages
              .lastWhere(
                (m) => m.isUser,
                orElse: () => ChatMessage(
                  role: ChatRole.user,
                  text: '',
                  timestamp: DateTime(2000),
                ),
              )
              .text;
    final reply = (messages.isNotEmpty && !messages.last.isUser)
        ? messages.last
        : null;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        if (youSaid.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '"$youSaid"',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontStyle: FontStyle.italic,
                color: PetPulzTheme.textDark,
              ),
            ),
          ),
        if (reply != null && voice.state != VoiceState.listening)
          PetPulzCard(
            padding: const EdgeInsets.all(16),
            color: reply.isError ? const Color(0xFFFFEBEB) : Colors.white,
            child: reply.isError
                ? Text(
                    reply.text,
                    style: const TextStyle(color: Colors.redAccent),
                  )
                : MarkdownBody(data: reply.text),
          ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PetPulzTheme.pillBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: PetPulzTheme.primaryPurple, fontWeight: FontWeight.w600),
      ),
    );
  }
}
