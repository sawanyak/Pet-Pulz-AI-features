import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_care_ai/chat/chat_controller.dart';
import 'package:pet_care_ai/chat/chat_history.dart';
import 'package:pet_care_ai/main.dart';
import 'package:pet_care_ai/profile/cat_profile_store.dart';
import 'package:pet_core/pet_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Ai implements AiService {
  @override
  Stream<String> replyStream(
    List<ChatMessage> history, {
    required CatProfile? cat,
    required bool spoken,
  }) async* {
    yield 'ok';
  }
}

Future<PrefsChatStore> _store([Map<String, Object> initial = const {}]) async {
  SharedPreferences.setMockInitialValues(initial);
  return PrefsChatStore.open();
}

Future<ChatController> _controller(ChatStore store) async =>
    ChatController(_Ai(), await CatProfileStore.load(), store: store);

void main() {
  group('multiple chats', () {
    test('new chat keeps the old one in the list', () async {
      final store = await _store();
      final c = await _controller(store);
      await c.send('first question');
      c.newChat();
      expect(c.messages, isEmpty);
      await c.send('second question');

      expect(c.sessions.length, 2);
      expect(c.sessions.map((s) => s.title),
          containsAll(['first question', 'second question']));
    });

    test('new chat does nothing when the chat is already blank', () async {
      final c = await _controller(await _store());
      c.newChat();
      c.newChat();
      expect(c.sessions.length, 1);
    });

    test('selecting a chat shows its messages', () async {
      final c = await _controller(await _store());
      await c.send('one');
      final firstId = c.activeChatId;
      c.newChat();
      await c.send('two');
      c.selectChat(firstId);
      expect(c.messages.first.text, 'one');
    });

    test('deleting the open chat opens another; deleting all leaves a blank',
        () async {
      final c = await _controller(await _store());
      await c.send('one');
      final firstId = c.activeChatId;
      c.newChat();
      await c.send('two');
      c.deleteChat(c.activeChatId);
      expect(c.activeChatId, firstId);
      c.deleteChat(firstId);
      expect(c.messages, isEmpty);
      expect(c.sessions.length, 1);
    });

    test('chats are saved and come back after a restart', () async {
      final store = await _store();
      final c = await _controller(store);
      await c.send('one');
      c.newChat();
      await c.send('two');
      await Future<void>.delayed(Duration.zero);

      final again = await _controller(PrefsChatStore(
        await SharedPreferences.getInstance(),
      ));
      expect(again.sessions.length, 2);
    });

    test('an older single saved chat becomes the first chat', () async {
      final legacy = await _store();
      expect(legacy.load(), isEmpty);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await PrefsChatHistory(prefs).save([
        ChatMessage(
          role: ChatRole.user,
          text: 'old question',
          timestamp: DateTime(2026),
        ),
      ]);
      final c = await _controller(PrefsChatStore(prefs));
      expect(c.sessions.single.title, 'old question');
    });
  });

  testWidgets('chat history drawer: new chat, switch and delete', (t) async {
    final store = await _store();
    await t.pumpWidget(
      PetCareApp(
        profileStore: await CatProfileStore.load(),
        chatStore: store,
        aiOverride: _Ai(),
      ),
    );
    await t.tap(find.byTooltip('Chat with Pet Pulz AI'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'hello there');
    await t.tap(find.byIcon(Icons.send_rounded));
    await t.pumpAndSettle();

    await t.tap(find.byTooltip('Chat history'));
    await t.pumpAndSettle();
    expect(find.text('hello there'), findsWidgets);
    await t.tap(find.text('New chat'));
    await t.pumpAndSettle();
    expect(find.text('ok'), findsNothing);

    await t.tap(find.byTooltip('Chat history'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Delete chat').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    // The blank chat is gone; only the "hello there" chat is left.
    expect(find.byTooltip('Delete chat'), findsOneWidget);
  });
}
