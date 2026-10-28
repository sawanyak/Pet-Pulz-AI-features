import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet_care_ai/chat/chat_controller.dart';
import 'package:pet_care_ai/main.dart';
import 'package:pet_core/pet_core.dart';
import 'package:pet_care_ai/profile/cat_profile_store.dart';
import 'package:pet_care_ai/voice/speech_io.dart';
import 'package:pet_care_ai/voice/voice_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------- fakes

/// A microphone we control by hand: the test "speaks" by calling emit().
class FakeInput implements SpeechInput {
  bool canInitialize = true;
  int starts = 0, stops = 0, cancels = 0;
  SpeechResultCallback? _onResult;
  SpeechFailureCallback? _onFailure;
  String _last = '';

  @override
  Future<bool> initialize() async => canInitialize;

  @override
  Future<void> start({
    required SpeechResultCallback onResult,
    required SpeechFailureCallback onFailure,
  }) async {
    starts++;
    _onResult = onResult;
    _onFailure = onFailure;
    _last = '';
  }

  /// Like the real recogniser: stop() ends the session with what was heard.
  @override
  Future<void> stop() async {
    stops++;
    _last.isEmpty ? fail(SpeechFailure.noSpeech) : emit(_last, isFinal: true);
  }

  @override
  Future<void> cancel() async {
    cancels++;
    _onResult = null;
    _onFailure = null;
  }

  void emit(String text, {bool isFinal = false}) {
    _last = text;
    _onResult?.call(SpeechResult(text, isFinal: isFinal));
  }

  void fail(SpeechFailure f) => _onFailure?.call(f);
}

/// A speaker that records sentences. With [holdSpeech] a sentence "keeps
/// talking" until stop() or release(), so we can test interrupting.
class FakeOutput implements SpeechOutput {
  final spoken = <String>[];
  bool holdSpeech = false;
  int stops = 0, prepares = 0;
  Completer<void>? _gate;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> prepare() async => prepares++;

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
    if (holdSpeech) {
      _gate = Completer<void>();
      await _gate!.future;
    } else {
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  Future<void> stop() async {
    stops++;
    if (_gate != null && !_gate!.isCompleted) _gate!.complete();
  }
}

/// An AI whose reply we push in piece by piece.
class StreamAi implements AiService {
  final _c = StreamController<String>();
  bool? lastSpoken;

  @override
  Stream<String> replyStream(
    List<ChatMessage> history, {
    required CatProfile? cat,
    required bool spoken,
  }) {
    lastSpoken = spoken;
    return _c.stream;
  }

  void push(String s) => _c.add(s);
  void fail(String message) => _c.addError(AiServiceException(message));
  Future<void> finish() => _c.close();
}

// ---------------------------------------------------------------- helpers

Future<void> settle() => pumpEventQueue(times: 200);

class Rig {
  Rig(this.ai, this.chat, this.input, this.output, this.voice);
  final StreamAi ai;
  final ChatController chat;
  final FakeInput input;
  final FakeOutput output;
  final VoiceController voice;
}

Future<Rig> rig({int maxSilentRounds = 2}) async {
  SharedPreferences.setMockInitialValues({});
  final ai = StreamAi();
  final chat = ChatController(ai, await CatProfileStore.load());
  final input = FakeInput();
  final output = FakeOutput();
  final voice = VoiceController(
    chat: chat,
    input: input,
    output: output,
    maxSilentRounds: maxSilentRounds,
    restartDelay: Duration.zero,
  );
  return Rig(ai, chat, input, output, voice);
}

// ------------------------------------------------------------------ tests

void main() {
  group('VoiceController conversation loop', () {
    test(
      'listen -> think -> speak sentence by sentence -> listen again',
      () async {
        final r = await rig();

        await r.voice.start();
        await settle();
        expect(r.voice.state, VoiceState.listening);
        expect(r.input.starts, 1);

        // Live draft shows up as the owner talks.
        r.input.emit('why does she');
        expect(r.voice.transcript, 'why does she');
        expect(r.chat.messages, isEmpty); // not sent yet

        r.input.emit('why does she scratch the sofa?', isFinal: true);
        await settle();
        expect(r.voice.state, VoiceState.thinking);
        expect(r.chat.messages.first.text, 'why does she scratch the sofa?');

        // First sentence is complete: spoken NOW, while the AI is still writing.
        r.ai.push('Cats scratch to mark their territory. They also stretch');
        await settle();
        expect(r.output.spoken, ['Cats scratch to mark their territory.']);
        expect(r.voice.state, VoiceState.speaking);

        // Rest of the reply arrives; the unfinished tail is flushed at the end.
        r.ai.push(' their muscles.');
        await r.ai.finish();
        await settle();
        expect(r.output.spoken.last, 'They also stretch their muscles.');

        // Hands-free: the microphone opens again by itself.
        expect(r.voice.state, VoiceState.listening);
        expect(r.input.starts, 2);
        expect(r.output.prepares, 1); // audio route set once per reply
      },
    );

    test('asks the AI for a spoken-style answer', () async {
      final r = await rig();
      await r.voice.start();
      r.input.emit('hello', isFinal: true);
      await settle();
      expect(r.ai.lastSpoken, isTrue); // the controller asks for a spoken style
    });

    test('markdown and emoji are not read out', () async {
      final r = await rig();
      await r.voice.start();
      r.input.emit('hi', isFinal: true);
      await settle();
      r.ai.push('**Great** question, my friend! Luna loves *boxes* 🐱\n');
      await r.ai.finish();
      await settle();
      final said = r.output.spoken.join(' ');
      expect(said, contains('Great question'));
      expect(said, isNot(contains('*')));
      expect(said, isNot(contains('🐱')));
    });

    test('an empty final result counts as silence', () async {
      final r = await rig();
      await r.voice.start();
      r.input.emit('   ', isFinal: true);
      await settle();
      expect(r.chat.messages, isEmpty);
      expect(r.input.starts, 2); // listened again
    });
  });

  group('VoiceController silence and failures', () {
    test('gives up after repeated silence and closes the microphone', () async {
      final r = await rig(maxSilentRounds: 2);
      await r.voice.start();
      for (var i = 0; i < 3; i++) {
        r.input.fail(SpeechFailure.noSpeech);
        await settle();
      }
      expect(r.input.starts, 3); // 1 + two retries, then it stops
      expect(r.voice.state, VoiceState.idle);
      expect(r.voice.isActive, isFalse);
      expect(r.voice.notice, contains('didn\'t hear'));
    });

    test('hearing something resets the silence counter', () async {
      final r = await rig(maxSilentRounds: 1);
      await r.voice.start();
      r.input.fail(SpeechFailure.noSpeech);
      await settle();
      r.input.emit('hello', isFinal: true);
      await settle();
      await r.ai.finish();
      await settle();
      // Back to listening with a fresh counter: one more silence is fine.
      r.input.fail(SpeechFailure.noSpeech);
      await settle();
      expect(r.voice.isActive, isTrue);
    });

    test('permission denied shows a helpful notice', () async {
      final r = await rig();
      await r.voice.start();
      r.input.fail(SpeechFailure.permission);
      await settle();
      expect(r.voice.state, VoiceState.idle);
      expect(r.voice.notice, contains('Microphone access'));
    });

    test('voice unavailable at start', () async {
      final r = await rig();
      r.input.canInitialize = false;
      await r.voice.start();
      await settle();
      expect(r.input.starts, 0);
      expect(r.voice.state, VoiceState.idle);
      expect(r.voice.notice, contains('isn\'t available'));
    });

    test('an AI error is read aloud and the loop stops', () async {
      final r = await rig();
      await r.voice.start();
      r.input.emit('hi', isFinal: true);
      await settle();
      r.ai.fail('No internet connection.');
      await r.ai.finish();
      await settle();

      expect(r.output.spoken, ['No internet connection.']);
      expect(r.voice.state, VoiceState.idle);
      expect(r.input.starts, 1); // did NOT start listening again
    });
  });

  group('VoiceController interruption', () {
    test('tapping the orb while speaking stops speech and listens', () async {
      final r = await rig();
      r.output.holdSpeech = true; // the sentence "keeps talking"
      await r.voice.start();
      r.input.emit('hi', isFinal: true);
      await settle();
      r.ai.push('Cats scratch to mark their territory. And more words here');
      await settle();
      expect(r.voice.state, VoiceState.speaking);
      expect(r.chat.isBusy, isTrue); // AI still writing

      await r.voice.onOrbTap(); // interrupt
      await settle();

      expect(r.output.stops, greaterThanOrEqualTo(1));
      expect(r.chat.isBusy, isFalse); // reply cancelled
      expect(r.voice.state, VoiceState.listening);
      expect(r.input.starts, 2);
      expect(r.output.spoken.length, 1); // nothing more was spoken
    });

    test('tapping the orb while thinking cancels and listens', () async {
      final r = await rig();
      await r.voice.start();
      r.input.emit('hi', isFinal: true);
      await settle();
      expect(r.voice.state, VoiceState.thinking);

      await r.voice.onOrbTap();
      await settle();
      expect(r.chat.isBusy, isFalse);
      expect(r.voice.state, VoiceState.listening);
    });

    test('tapping the orb while listening means "I\'m done talking"', () async {
      final r = await rig();
      await r.voice.start();
      r.input.emit('is she ok', isFinal: false);
      await r.voice.onOrbTap();
      await settle();
      expect(r.input.stops, 1);
      expect(r.chat.messages.first.text, 'is she ok'); // sent
    });

    test('tapping the orb when idle starts a session', () async {
      final r = await rig();
      await r.voice.onOrbTap();
      await settle();
      expect(r.voice.state, VoiceState.listening);
    });

    test('stop() ends everything', () async {
      final r = await rig();
      await r.voice.start();
      r.input.emit('hi', isFinal: true);
      await settle();
      r.ai.push('Cats scratch to mark their territory. More');
      await settle();

      await r.voice.stop();
      await settle();
      expect(r.voice.state, VoiceState.idle);
      expect(r.voice.isActive, isFalse);
      expect(r.input.cancels, greaterThanOrEqualTo(1));
      expect(r.chat.isBusy, isFalse);
      expect(r.input.starts, 1); // never re-listens after stop
    });

    test('dispose mid-reply is safe', () async {
      final r = await rig();
      await r.voice.start();
      r.input.emit('hi', isFinal: true);
      await settle();
      r.ai.push('Cats scratch to mark their territory. More');
      await settle();

      r.voice.dispose();
      await settle();
      expect(r.chat.isBusy, isFalse);
      expect(r.input.cancels, greaterThanOrEqualTo(1));
    });
  });

  group('Voice screen', () {
    Future<(FakeInput, FakeOutput)> openVoiceScreen(
      WidgetTester tester, {
      bool canInitialize = true,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final input = FakeInput()..canInitialize = canInitialize;
      final output = FakeOutput();
      await tester.pumpWidget(
        PetCareApp(
          profileStore: await CatProfileStore.load(),
          aiOverride: MockAiService(delay: Duration.zero),
          speechInput: input,
          speechOutput: output,
        ),
      );
      await tester.tap(find.byTooltip('Chat with Pet Pulz AI'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Voice mode'));
      // The orb animates forever, so pumpAndSettle would never finish.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 100));
      return (input, output);
    }

    /// Taps the X and waits for the pop animation to fully finish.
    Future<void> closeVoiceScreen(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Close'));
      // An animation only starts counting on its FIRST frame, so: one frame
      // to start it, one long enough to finish it, one to remove the route.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('shows listening state and the live transcript', (
      tester,
    ) async {
      final (input, _) = await openVoiceScreen(tester);
      expect(find.text('Listening...'), findsOneWidget);

      input.emit('my cat is sneezing');
      await tester.pump();
      expect(find.text('"my cat is sneezing"'), findsOneWidget);
    });

    testWidgets('closing the screen releases the microphone', (tester) async {
      final (input, output) = await openVoiceScreen(tester);
      await closeVoiceScreen(tester);
      expect(input.cancels, greaterThanOrEqualTo(1));
      expect(output.stops, greaterThanOrEqualTo(1));
      expect(find.text('Voice mode'), findsNothing);
    });

    testWidgets('unavailable voice input explains why', (tester) async {
      await openVoiceScreen(tester, canInitialize: false);
      expect(find.text('Tap to talk'), findsOneWidget);
      expect(find.textContaining('isn\'t available'), findsOneWidget);
    });

    testWidgets('a spoken question appears in the normal chat', (tester) async {
      final (input, _) = await openVoiceScreen(tester);
      input.emit('why does she purr', isFinal: true);
      await tester.pump(const Duration(seconds: 3));
      await closeVoiceScreen(tester);
      expect(find.text('Voice mode'), findsNothing); // really back on the chat
      expect(find.text('why does she purr'), findsOneWidget);
    });
  });
}
