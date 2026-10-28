import 'package:flutter/foundation.dart';

import '../chat/chat_controller.dart';
import 'speech_io.dart';
import 'speech_text.dart';

/// What the voice assistant is doing right now. The screen just draws
/// whichever state this is.
enum VoiceState {
  /// Not in a conversation. Tap the orb to start.
  idle,

  /// The microphone is open and we're waiting for / hearing the owner.
  listening,

  /// The owner finished; waiting for the AI's first words.
  thinking,

  /// The AI's answer is being read aloud.
  speaking,
}

/// Runs the hands-free conversation loop:
///
///     listen -> send text to the AI -> speak the answer -> listen again ...
///
/// It reuses the SAME [ChatController] as the text chat, so what you say and
/// what the assistant answers also show up in the normal chat history.
///
/// The tricky part is time. Many things happen "later" (speech results, AI
/// words arriving, the speaker finishing) and the user can interrupt at any
/// moment. To stay safe every phase gets a number, [_epoch]. Any late
/// callback checks "is my number still current?" and quietly does nothing
/// if the conversation has moved on.
class VoiceController extends ChangeNotifier {
  VoiceController({
    required this.chat,
    required this.input,
    required this.output,
    this.maxSilentRounds = 2,
    this.restartDelay = const Duration(milliseconds: 400),
  });

  final ChatController chat;
  final SpeechInput input;
  final SpeechOutput output;

  /// After this many listening rounds in a row with no speech, we stop
  /// listening instead of keeping the microphone open forever.
  final int maxSilentRounds;

  /// Short pause before re-opening the microphone (avoids a tight loop).
  final Duration restartDelay;

  VoiceState _state = VoiceState.idle;
  String _transcript = '';
  String? _notice;
  bool _active = false; // hands-free session on?
  bool _initialized = false;
  bool _disposed = false;
  int _epoch = 0;
  int _silentRounds = 0;

  // --- per-turn bookkeeping (one turn = one question + its spoken answer)
  final List<String> _queue = []; // sentences waiting to be spoken
  int _replyIndex = 0; // index in chat.messages where the AI's reply lands
  int _consumed = 0; // how many characters of the reply we've already queued
  int _turnEpoch = -1;
  bool _replyDone = false;
  bool _pumping = false; // a loop is currently speaking the queue
  bool _turnSpeaking = false;
  bool _turnFailed = false;

  VoiceState get state => _state;

  /// Live text of what the owner is saying (or just said).
  String get transcript => _transcript;

  /// A friendly explanation when something needs the user's attention.
  String? get notice => _notice;

  /// True while a hands-free session is running.
  bool get isActive => _active;

  // ---------------------------------------------------------------- public

  /// Starts a hands-free session (asks for permissions the first time).
  Future<void> start() async {
    if (_active) return;
    _active = true;
    _notice = null;
    _silentRounds = 0;
    final epoch = ++_epoch;
    _notify();

    if (!_initialized) {
      final ok = await input.initialize();
      if (epoch != _epoch) return;
      if (!ok) {
        _fail(
          'Voice input isn\'t available. Check that microphone and '
          'speech recognition are allowed for this app in Settings.',
        );
        return;
      }
      await output.initialize();
      if (epoch != _epoch) return;
      _initialized = true;
    }
    await _listen();
  }

  /// Ends the session: stops listening, speaking and any reply in progress.
  Future<void> stop() async {
    _epoch++;
    _active = false;
    _queue.clear();
    _pumping = false;
    chat.removeListener(_onChat);
    _state = VoiceState.idle;
    _transcript = '';
    _notify();
    await input.cancel();
    await output.stop();
    if (chat.isBusy) chat.stopReply();
  }

  /// The big orb was tapped. What it does depends on the moment:
  /// idle -> start, listening -> "I'm done talking", otherwise -> interrupt.
  Future<void> onOrbTap() async {
    switch (_state) {
      case VoiceState.idle:
        await start();
      case VoiceState.listening:
        await input.stop(); // delivers what was heard as the final result
      case VoiceState.thinking:
      case VoiceState.speaking:
        await _interrupt();
    }
  }

  // --------------------------------------------------------------- listening

  Future<void> _listen() async {
    if (!_active || _disposed) return;
    final epoch = ++_epoch;
    _state = VoiceState.listening;
    _transcript = '';
    _notify();

    await input.start(
      onResult: (r) {
        if (epoch != _epoch) return;
        _transcript = r.text;
        _notify();
        if (!r.isFinal) return;
        final text = r.text.trim();
        text.isEmpty ? _onSilence() : _handleUtterance(text);
      },
      onFailure: (f) {
        if (epoch != _epoch) return;
        switch (f) {
          case SpeechFailure.noSpeech:
            _onSilence();
          case SpeechFailure.permission:
            _fail(
              'Microphone access was denied. Enable it for this app in '
              'Settings to use voice.',
            );
          case SpeechFailure.other:
            _fail('Voice input stopped working. Tap the mic to try again.');
        }
      },
    );
  }

  void _onSilence() {
    _silentRounds++;
    if (_silentRounds > maxSilentRounds) {
      // Give up politely instead of leaving the microphone open forever.
      _active = false;
      _state = VoiceState.idle;
      _notice = 'I didn\'t hear anything. Tap the mic when you\'re ready.';
      _notify();
      return;
    }
    final epoch = _epoch;
    Future<void>.delayed(restartDelay, () {
      if (epoch != _epoch) return; // something else happened meanwhile
      _listen();
    });
  }

  void _fail(String message) {
    _epoch++;
    _active = false;
    _state = VoiceState.idle;
    _notice = message;
    _notify();
  }

  // ---------------------------------------------------- one question + answer

  Future<void> _handleUtterance(String text) async {
    _silentRounds = 0;
    final epoch = ++_epoch;
    _turnEpoch = epoch;
    _state = VoiceState.thinking;
    _transcript = text;
    _queue.clear();
    _consumed = 0;
    _replyDone = false;
    _pumping = false;
    _turnSpeaking = false;
    _turnFailed = false;
    if (chat.isBusy) chat.stopReply(); // never overlap with an old reply
    // After send(), messages are [..., user, reply], so the reply is at +1.
    _replyIndex = chat.messages.length + 1;
    _notify();

    chat.addListener(_onChat);
    try {
      await chat.send(text, spoken: true);
    } finally {
      chat.removeListener(_onChat);
    }
    if (epoch != _epoch) return; // interrupted or stopped while waiting

    _queueReply(flush: true);
    _replyDone = true;
    _maybeFinishTurn(epoch);
  }

  /// The chat changed: new words of the reply may have arrived.
  void _onChat() {
    if (_turnEpoch != _epoch) return;
    _queueReply(flush: false);
  }

  /// Moves newly arrived reply text into the speaking queue.
  /// [flush] = the reply is complete, so also speak the unfinished tail.
  void _queueReply({required bool flush}) {
    final messages = chat.messages;
    if (messages.length <= _replyIndex) return;

    final reply = messages[_replyIndex];
    if (!reply.isError) {
      final pending = reply.text.substring(_consumed);
      if (flush) {
        _consumed = reply.text.length;
        _enqueue(pending);
      } else {
        final split = splitSentences(pending);
        _consumed += pending.length - split.rest.length;
        split.complete.forEach(_enqueue);
      }
    }

    if (flush) {
      // An error bubble (from the reply itself or after a partial one):
      // read it out so a hands-free user knows what happened, then stop
      // the loop instead of retrying forever.
      for (final m in messages.skip(_replyIndex)) {
        if (m.isError) {
          _turnFailed = true;
          _enqueue(m.text);
        }
      }
    }
  }

  void _enqueue(String raw) {
    final text = speakableText(raw);
    if (text.isEmpty) return;
    _queue.add(text);
    _pump();
  }

  /// Speaks queued sentences one after another. Safe to call repeatedly:
  /// only one loop runs at a time and new sentences join the queue.
  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    final epoch = _epoch;

    if (!_turnSpeaking) {
      _turnSpeaking = true;
      _state = VoiceState.speaking;
      _notify();
      await output.prepare();
    }
    while (_queue.isNotEmpty && epoch == _epoch) {
      await output.speak(_queue.removeAt(0));
    }
    if (epoch != _epoch) return; // a newer phase owns the state now

    _pumping = false;
    _maybeFinishTurn(epoch);
  }

  /// Called whenever something might have finished the turn. Only acts when
  /// the reply is complete AND everything has been spoken.
  void _maybeFinishTurn(int epoch) {
    if (epoch != _epoch || !_replyDone || _pumping || _queue.isNotEmpty) {
      return;
    }
    if (_turnFailed || !_active) {
      _active = false;
      _state = VoiceState.idle;
      _notify();
      return;
    }
    _listen(); // hands-free: take the next question
  }

  // ---------------------------------------------------------------- interrupt

  Future<void> _interrupt() async {
    _epoch++; // everything in flight becomes stale
    _queue.clear();
    _pumping = false;
    chat.removeListener(_onChat);
    await output.stop();
    if (chat.isBusy) chat.stopReply();
    _active = true;
    _silentRounds = 0;
    await _listen();
  }

  // ------------------------------------------------------------------ cleanup

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _queue.clear();
    chat.removeListener(_onChat);
    // Fire and forget: we can't await in dispose().
    input.cancel();
    output.stop();
    if (chat.isBusy) chat.stopReply();
    super.dispose();
  }
}
