import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_care_ai/chat/chat_controller.dart';
import 'package:pet_care_ai/chat/chat_history.dart';
import 'package:pet_care_ai/main.dart';
import 'package:pet_core/pet_core.dart';
import 'package:pet_care_ai/profile/cat_profile_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

ChatMessage msg(String text, {bool user = true, bool error = false}) =>
    ChatMessage(
      role: user ? ChatRole.user : ChatRole.assistant,
      text: text,
      timestamp: DateTime(2026, 9, 30, 12),
      isError: error,
    );

/// Captures what the AI is sent, and replies with pieces you control.
class CapturingAi implements AiService {
  List<ChatMessage>? lastHistory;
  final List<String> reply;
  CapturingAi([this.reply = const ['ok']]);

  @override
  Stream<String> replyStream(
    List<ChatMessage> history, {
    required CatProfile? cat,
    required bool spoken,
  }) async* {
    lastHistory = history;
    for (final p in reply) {
      yield p;
    }
  }
}

class GatedAi implements AiService {
  bool cancelled = false;
  late final _c = StreamController<String>(onCancel: () => cancelled = true);
  @override
  Stream<String> replyStream(
    List<ChatMessage> history, {
    required CatProfile? cat,
    required bool spoken,
  }) => _c.stream;
  void push(String s) => _c.add(s);
  Future<void> finish() => _c.close();
}

/// A history whose writes always fail.
class BrokenHistory implements ChatHistory {
  @override
  List<ChatMessage> load() => const [];
  @override
  Future<void> save(List<ChatMessage> messages) async =>
      throw Exception('disk full');
  @override
  Future<void> clear() async => throw Exception('disk full');
}

Future<PrefsChatHistory> open([Map<String, Object> initial = const {}]) async {
  SharedPreferences.setMockInitialValues(initial);
  return PrefsChatHistory.open();
}

Future<CatProfileStore> profiles() => CatProfileStore.load();

void main() {
  group('ChatMessage JSON', () {
    test('round trip', () {
      final m = ChatMessage.tryFromJson(msg('hello', user: false).toJson())!;
      expect(m.text, 'hello');
      expect(m.role, ChatRole.assistant);
      expect(m.timestamp, DateTime(2026, 9, 30, 12));
    });

    test('junk entries return null instead of throwing', () {
      for (final junk in <Object?>[
        null,
        'x',
        5,
        {},
        {'role': 'user', 'text': '', 'time': '2026-01-01T00:00:00'},
        {'role': 'robot', 'text': 'hi', 'time': '2026-01-01T00:00:00'},
        {'role': 'user', 'text': 'hi', 'time': 'not a date'},
        {'role': 'user', 'text': 5, 'time': '2026-01-01T00:00:00'},
      ]) {
        expect(ChatMessage.tryFromJson(junk), isNull, reason: '$junk');
      }
    });
  });

  group('PrefsChatHistory', () {
    test('saves and loads in order', () async {
      final h = await open();
      await h.save([msg('q'), msg('a', user: false)]);
      final loaded = PrefsChatHistory(
        await SharedPreferences.getInstance(),
      ).load();
      expect(loaded.map((m) => m.text), ['q', 'a']);
    });

    test('error bubbles are not saved', () async {
      final h = await open();
      await h.save([msg('q'), msg('No internet', user: false, error: true)]);
      expect(h.load().map((m) => m.text), ['q']);
    });

    test('only the newest ${PrefsChatHistory.maxSaved} are kept', () async {
      final h = await open();
      await h.save([for (var i = 0; i < 250; i++) msg('m$i')]);
      final loaded = h.load();
      expect(loaded.length, PrefsChatHistory.maxSaved);
      expect(loaded.first.text, 'm50');
      expect(loaded.last.text, 'm249');
    });

    test(
      'damaged data gives an empty chat, one bad entry is skipped',
      () async {
        expect((await open({'chat_history_v1': '{oops'})).load(), isEmpty);
        final h = await open({
          'chat_history_v1':
              '[{"role":"user","text":"kept","time":"2026-01-01T00:00:00"},'
              '"garbage",{"role":"x"}]',
        });
        expect(h.load().map((m) => m.text), ['kept']);
      },
    );

    test('clear removes it', () async {
      final h = await open();
      await h.save([msg('q')]);
      await h.clear();
      expect(h.load(), isEmpty);
    });
  });

  group('contextWindow', () {
    test('short chats are sent whole', () {
      final w = contextWindow([msg('a'), msg('b', user: false)]);
      expect(w.length, 2);
    });

    test('long chats are cut to the newest messages', () {
      final all = [for (var i = 0; i < 100; i++) msg('m$i', user: i.isEven)];
      final w = contextWindow(all, max: 10);
      expect(w.length, lessThanOrEqualTo(10));
      expect(w.last.text, 'm99');
    });

    test('never starts with an assistant message', () {
      // 5 messages: u a u a u ; keeping the last 4 would start with "a".
      final all = [for (var i = 0; i < 5; i++) msg('m$i', user: i.isEven)];
      final w = contextWindow(all, max: 4);
      expect(w.first.isUser, isTrue);
      expect(w.map((m) => m.text), ['m2', 'm3', 'm4']);
    });

    test('error bubbles are never sent', () {
      final w = contextWindow([
        msg('q'),
        msg('err', user: false, error: true),
        msg('q2'),
      ]);
      expect(w.map((m) => m.text), ['q', 'q2']);
    });
  });

  group('ChatController with history', () {
    test('a saved conversation is restored', () async {
      final h = await open();
      await h.save([msg('old question'), msg('old answer', user: false)]);

      final c = ChatController(CapturingAi(), await profiles(), history: h);
      expect(c.messages.map((m) => m.text), ['old question', 'old answer']);
    });

    test('the AI is only sent the recent window of a long chat', () async {
      final h = await open();
      await h.save([for (var i = 0; i < 120; i++) msg('m$i', user: i.isEven)]);
      final ai = CapturingAi();
      final c = ChatController(ai, await profiles(), history: h);

      await c.send('new question');
      expect(ai.lastHistory!.length, lessThanOrEqualTo(31));
      expect(ai.lastHistory!.last.text, 'new question');
      expect(ai.lastHistory!.first.isUser, isTrue);
      expect(c.messages.length, 122); // the screen still shows everything
    });

    test('a finished exchange is saved', () async {
      final h = await open();
      final c = ChatController(
        CapturingAi(['Hello ', 'there']),
        await profiles(),
        history: h,
      );
      await c.send('hi');
      await pumpEventQueue();
      expect(h.load().map((m) => m.text), ['hi', 'Hello there']);
    });

    test('the question is saved immediately, before the answer', () async {
      final h = await open();
      final ai = GatedAi();
      final c = ChatController(ai, await profiles(), history: h);
      final sending = c.send('are you there');
      await pumpEventQueue();
      expect(h.load().map((m) => m.text), ['are you there']);
      ai.push('yes');
      await ai.finish();
      await sending;
    });

    test('a reply stopped halfway keeps the part that arrived', () async {
      final h = await open();
      final ai = GatedAi();
      final c = ChatController(ai, await profiles(), history: h);
      final sending = c.send('tell me a story');
      ai.push('Once upon a time');
      await pumpEventQueue();
      c.stopReply();
      await sending;
      await pumpEventQueue();
      expect(h.load().map((m) => m.text), [
        'tell me a story',
        'Once upon a time',
      ]);
    });

    test('stopping closes the connection to the AI immediately', () async {
      final ai = GatedAi();
      final c = ChatController(ai, await profiles());
      final sending = c.send('hello');
      await pumpEventQueue();
      expect(ai.cancelled, isFalse);

      // Still "thinking": no word has arrived yet. send() must not have to
      // wait for one before it notices the stop.
      c.stopReply();
      await sending.timeout(const Duration(seconds: 2));
      expect(ai.cancelled, isTrue);
      expect(c.isBusy, isFalse);
    });

    test('New chat also closes the connection', () async {
      final ai = GatedAi();
      final c = ChatController(ai, await profiles());
      final sending = c.send('hello');
      ai.push('partial');
      await pumpEventQueue();
      c.clear();
      await sending.timeout(const Duration(seconds: 2));
      expect(ai.cancelled, isTrue);
      expect(c.messages, isEmpty);
    });

    test('an error bubble is not saved', () async {
      final h = await open();
      final c = ChatController(_FailingAi(), await profiles(), history: h);
      await c.send('hi');
      await pumpEventQueue();
      expect(c.messages.last.isError, isTrue);
      expect(h.load().map((m) => m.text), ['hi']);
    });

    test('New chat forgets the saved conversation', () async {
      final h = await open();
      final c = ChatController(CapturingAi(), await profiles(), history: h);
      await c.send('hi');
      await pumpEventQueue();
      c.clear();
      await pumpEventQueue();
      expect(h.load(), isEmpty);
      // ...and a fresh controller starts empty.
      final again = ChatController(CapturingAi(), await profiles(), history: h);
      expect(again.messages, isEmpty);
    });

    test('a storage failure never breaks the chat', () async {
      final c = ChatController(
        CapturingAi(['fine']),
        await profiles(),
        history: BrokenHistory(),
      );
      await c.send('hi');
      await pumpEventQueue();
      c.clear();
      await pumpEventQueue();
      expect(c.messages, isEmpty); // no exception escaped
    });

    test('without a history nothing changes (existing behaviour)', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ChatController(CapturingAi(), await profiles());
      await c.send('hi');
      expect(c.messages.length, 2);
    });
  });

  group('app restart', () {
    testWidgets('the chat comes back after the app is rebuilt', (t) async {
      SharedPreferences.setMockInitialValues({});
      final history = await PrefsChatHistory.open();
      final store = await profiles();

      Future<void> launch() async {
        await t.pumpWidget(
          PetCareApp(
            key: UniqueKey(), // a brand-new app, like a restart
            profileStore: store,
            chatHistory: history,
            aiOverride: MockAiService(
              delay: Duration.zero,
              wordDelay: Duration.zero,
            ),
          ),
        );
        await t.tap(find.byTooltip('Chat with Pet Pulz AI'));
        await t.pumpAndSettle();
      }

      await launch();
      await t.enterText(find.byType(TextField), 'Any games to play?');
      await t.tap(find.byIcon(Icons.send_rounded));
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();
      expect(find.textContaining('Wand toy', findRichText: true), findsWidgets);

      await launch(); // "restart"
      await t.pumpAndSettle();
      expect(find.text('Any games to play?'), findsOneWidget);
      expect(find.textContaining('Wand toy', findRichText: true), findsWidgets);
      expect(find.text('Hi, I\'m Whiskers!'), findsNothing); // not the welcome
    });
  });
}

class _FailingAi implements AiService {
  @override
  Stream<String> replyStream(
    List<ChatMessage> history, {
    required CatProfile? cat,
    required bool spoken,
  }) async* {
    throw AiServiceException('No internet connection.');
  }
}
