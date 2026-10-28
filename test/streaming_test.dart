import 'dart:async';
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pet_care_ai/chat/chat_controller.dart';
import 'package:pet_core/pet_core.dart';
import 'package:pet_care_ai/profile/cat_profile_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake HTTP client that answers with the given SSE lines, split into
/// awkward chunks (mid-line and mid-emoji) like a real network would.
http.Client sseClient(String body, {int status = 200}) =>
    MockClient.streaming((request, _) async {
      final bytes = utf8.encode(body);
      Stream<List<int>> chunks() async* {
        for (var i = 0; i < bytes.length; i += 7) {
          yield bytes.sublist(i, i + 7 > bytes.length ? bytes.length : i + 7);
        }
      }

      return http.StreamedResponse(chunks(), status);
    });

Future<CatProfileStore> emptyStore() async {
  SharedPreferences.setMockInitialValues({});
  return CatProfileStore.load();
}

final history = [
  ChatMessage(role: ChatRole.user, text: 'hi', timestamp: DateTime(2026)),
];

/// AI whose stream is scripted: yields [pieces], then optionally fails.
class ScriptedAi implements AiService {
  ScriptedAi(this.pieces, {this.failAfter = false});
  final List<String> pieces;
  final bool failAfter;
  int calls = 0;
  CatProfile? lastCat;
  bool? lastSpoken;

  @override
  Stream<String> replyStream(
    List<ChatMessage> history, {
    required CatProfile? cat,
    required bool spoken,
  }) async* {
    calls++;
    lastCat = cat;
    lastSpoken = spoken;
    for (final p in pieces) {
      yield p;
    }
    if (failAfter) throw AiServiceException('boom');
  }
}

void main() {
  setUpAll(() => dotenv.loadFromString(envString: '', isOptional: true));

  group('Claude SSE parsing', () {
    test('joins text_delta pieces, ignores other events, keeps emoji', () async {
      final body = [
        'event: message_start',
        'data: {"type":"message_start"}',
        '',
        'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello 🐱"}}',
        '',
        'data: {"type":"ping"}',
        '',
        'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":" there"}}',
        '',
      ].join('\n');
      final pieces = await ClaudeAiService(
        client: sseClient(body),
      ).replyStream(history, cat: null, spoken: false).toList();
      expect(pieces.join(), 'Hello 🐱 there');
    });

    test('maps HTTP 401 to a friendly error', () {
      final svc = ClaudeAiService(client: sseClient('{}', status: 401));
      expect(
        svc.replyStream(history, cat: null, spoken: false).toList(),
        throwsA(isA<AiServiceException>()),
      );
    });

    test('mid-stream overloaded error surfaces as AiServiceException', () {
      final body =
          'data: {"type":"error","error":{"type":"overloaded_error"}}\n\n';
      final svc = ClaudeAiService(client: sseClient(body));
      expect(
        svc.replyStream(history, cat: null, spoken: false).toList(),
        throwsA(isA<AiServiceException>()),
      );
    });
  });

  group('Gemini SSE parsing', () {
    test('joins text parts across chunks', () async {
      final body = [
        'data: {"candidates":[{"content":{"parts":[{"text":"Hel"}]}}]}',
        '',
        'data: {"candidates":[{"content":{"parts":[{"text":"lo"}]}}]}',
        '',
      ].join('\n');
      final pieces = await GeminiAiService(
        client: sseClient(body),
      ).replyStream(history, cat: null, spoken: false).toList();
      expect(pieces.join(), 'Hello');
    });

    test('blocked answer becomes a friendly error', () {
      final body = 'data: {"promptFeedback":{"blockReason":"SAFETY"}}\n\n';
      final svc = GeminiAiService(client: sseClient(body));
      expect(
        svc.replyStream(history, cat: null, spoken: false).toList(),
        throwsA(isA<AiServiceException>()),
      );
    });
  });

  group('ChatController streaming', () {
    test('bubble grows piece by piece and ends as one message', () async {
      final chat = ChatController(
        ScriptedAi(['Hel', 'lo ', 'world']),
        await emptyStore(),
      );
      final seen = <String>[];
      chat.addListener(() {
        if (chat.messages.isNotEmpty && !chat.messages.last.isUser) {
          seen.add(chat.messages.last.text);
        }
      });

      await chat.send('hi');

      expect(seen, containsAllInOrder(['Hel', 'Hello ', 'Hello world']));
      expect(chat.messages.map((m) => m.text), ['hi', 'Hello world']);
      expect(chat.isBusy, isFalse);
    });

    test(
      'mid-stream failure keeps partial text and adds an error bubble',
      () async {
        final chat = ChatController(
          ScriptedAi(['Partial'], failAfter: true),
          await emptyStore(),
        );
        await chat.send('hi');

        expect(chat.messages.map((m) => m.text), ['hi', 'Partial', 'boom']);
        expect(chat.messages.last.isError, isTrue);
        expect(chat.isBusy, isFalse);
      },
    );

    test('retry removes partial reply + error and resends once', () async {
      final ai = ScriptedAi(['Partial'], failAfter: true);
      final chat = ChatController(ai, await emptyStore());
      await chat.send('hi');
      await chat.retry();

      expect(ai.calls, 2);
      // One user message (not duplicated), partial, error - after retry.
      expect(chat.messages.where((m) => m.isUser).length, 1);
    });

    test('clear() during streaming discards the late reply', () async {
      final gate = Completer<void>();
      final ai = _GatedAi(gate.future);
      final chat = ChatController(ai, await emptyStore());

      final sending = chat.send('hi');
      await Future<void>.delayed(Duration.zero);
      chat.clear();
      gate.complete();
      await sending;

      expect(chat.messages, isEmpty);
      expect(chat.isBusy, isFalse);
    });
  });
}

class _GatedAi implements AiService {
  _GatedAi(this.gate);
  final Future<void> gate;

  @override
  Stream<String> replyStream(
    List<ChatMessage> history, {
    required CatProfile? cat,
    required bool spoken,
  }) async* {
    await gate;
    yield 'late reply';
  }
}
