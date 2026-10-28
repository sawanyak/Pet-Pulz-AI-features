import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pet_care_ai/app_services.dart';
import 'package:pet_care_ai/backend/backend_client.dart';
import 'package:pet_care_ai/backend/backend_services.dart';
import 'package:pet_care_ai/backend/backend_session.dart';
import 'package:pet_core/pet_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

final baseUrl = Uri.parse('http://localhost:8080');

class Seen {
  Seen(this.method, this.path, this.headers, this.body);
  final String method, path;
  final Map<String, String> headers;
  final String body;

  Map<String, dynamic> get json => jsonDecode(body) as Map<String, dynamic>;
}

/// Response of the fake server for one request.
typedef Reply = FutureOr<http.StreamedResponse> Function(Seen request);

http.StreamedResponse ok(Object body, {int status = 200}) =>
    http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      status,
      headers: {'content-type': 'application/json'},
    );

http.StreamedResponse sse(List<Object> lines, {int status = 200}) =>
    http.StreamedResponse(
      Stream.fromIterable([
        for (final l in lines) utf8.encode('data: ${jsonEncode(l)}\n\n'),
      ]),
      status,
      headers: {'content-type': 'text/event-stream'},
    );

http.StreamedResponse err(int status, String code, String message) =>
    ok(errorJson(code, message), status: status);

/// A fake backend: routes by path, records what it received.
class FakeServer {
  final seen = <Seen>[];
  final routes = <String, Reply>{};
  var tokenCounter = 0;
  DateTime expiresAt = DateTime.utc(2026, 10, 30);

  FakeServer() {
    routes[ApiRoutes.register] = (r) {
      tokenCounter++;
      return ok({
        'token': 'token-$tokenCounter',
        'expiresAt': expiresAt.toIso8601String(),
      });
    };
  }

  http.Client get client => MockClient.streaming((request, bodyStream) async {
    final body = await bodyStream.bytesToString();
    final s = Seen(request.method, request.url.path, request.headers, body);
    seen.add(s);
    final route = routes[request.url.path];
    if (route == null) return err(404, 'bad_request', 'Not found.');
    return route(s);
  });

  Iterable<Seen> to(String path) => seen.where((s) => s.path == path);
}

Future<(FakeServer, BackendClient, BackendSession)> setup({
  DateTime? now,
  Map<String, Object> prefsValues = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefsValues);
  final prefs = await SharedPreferences.getInstance();
  final server = FakeServer();
  final session = BackendSession(
    baseUrl: baseUrl,
    prefs: prefs,
    client: server.client,
    clock: () => now ?? DateTime.utc(2026, 9, 30, 12),
  );
  return (server, BackendClient(session), session);
}

ChatMessage msg(String text, {bool user = true, bool error = false}) =>
    ChatMessage(
      role: user ? ChatRole.user : ChatRole.assistant,
      text: text,
      timestamp: DateTime(2026),
      isError: error,
    );

final photo = ScreenerPhoto(
  bytes: Uint8List.fromList([1, 2, 3]),
  mimeType: 'image/jpeg',
);

Matcher failsWith(Object messageMatcher) => throwsA(
  isA<AiServiceException>().having((e) => e.message, 'message', messageMatcher),
);

void main() {
  group('BackendSession', () {
    test('registers on first use and remembers the token', () async {
      final (server, _, session) = await setup();
      expect(await session.token(), 'token-1');
      expect(await session.token(), 'token-1'); // cached
      expect(server.to(ApiRoutes.register).length, 1);
    });

    test(
      'the token survives an app restart (new session, same storage)',
      () async {
        final (server, _, _) = await setup();
        final prefs = await SharedPreferences.getInstance();
        BackendSession make() => BackendSession(
          baseUrl: baseUrl,
          prefs: prefs,
          client: server.client,
          clock: () => DateTime.utc(2026, 9, 30),
        );
        await make().token();
        expect(await make().token(), 'token-1');
        expect(server.to(ApiRoutes.register).length, 1);
      },
    );

    test('many simultaneous requests cause only ONE registration', () async {
      final (server, _, session) = await setup();
      final tokens = await Future.wait([
        for (var i = 0; i < 5; i++) session.token(),
      ]);
      expect(tokens.toSet(), {'token-1'});
      expect(server.to(ApiRoutes.register).length, 1);
    });

    test(
      'renews (presenting the old token) when under 7 days are left',
      () async {
        var now = DateTime.utc(2026, 9, 30);
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final server = FakeServer();
        final session = BackendSession(
          baseUrl: baseUrl,
          prefs: prefs,
          client: server.client,
          clock: () => now,
        );
        expect(await session.token(), 'token-1');

        now = DateTime.utc(2026, 10, 25); // 5 days left -> renew
        expect(await session.token(), 'token-2');
        expect(
          server.to(ApiRoutes.register).last.headers['authorization'],
          'Bearer token-1',
        );
      },
    );

    test('a failed renewal keeps using the still-valid old token', () async {
      var now = DateTime.utc(2026, 9, 30);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final server = FakeServer();
      final session = BackendSession(
        baseUrl: baseUrl,
        prefs: prefs,
        client: server.client,
        clock: () => now,
      );
      await session.token();
      now = DateTime.utc(2026, 10, 25);
      server.routes[ApiRoutes.register] = (r) => err(500, 'internal', 'x');
      expect(await session.token(), 'token-1');
    });

    test('with no token and no network, the message is friendly', () async {
      SharedPreferences.setMockInitialValues({});
      final session = BackendSession(
        baseUrl: baseUrl,
        prefs: await SharedPreferences.getInstance(),
        client: MockClient((r) async => throw http.ClientException('down')),
      );
      expect(session.token(), failsWith(contains('reach the Whiskers')));
    });

    test('reset forgets the token', () async {
      final (server, _, session) = await setup();
      await session.token();
      await session.reset();
      expect(await session.token(), 'token-2');
      expect(server.to(ApiRoutes.register).length, 2);
    });
  });

  group('BackendAiService (chat)', () {
    Stream<String> ask(BackendClient c, {bool spoken = false}) =>
        BackendAiService(c).replyStream([msg('hi')], cat: null, spoken: spoken);

    test('streams deltas and stops at done', () async {
      final (server, client, _) = await setup();
      server.routes[ApiRoutes.chat] = (r) => sse([
        {'type': 'delta', 'text': 'Hello '},
        {'type': 'delta', 'text': 'there'},
        {'type': 'done'},
      ]);
      expect(await ask(client).toList(), ['Hello ', 'there']);
    });

    test(
      'sends the conversation, cat and spoken flag, with the token',
      () async {
        final (server, client, _) = await setup();
        server.routes[ApiRoutes.chat] = (r) => sse([
          {'type': 'delta', 'text': 'ok'},
          {'type': 'done'},
        ]);
        await BackendAiService(client)
            .replyStream(
              [
                msg('q1'),
                msg('a1', user: false),
                msg('No internet', user: false, error: true), // never sent
                msg('q2'),
              ],
              cat: const CatProfile(name: 'Luna', ageYears: 3),
              spoken: true,
            )
            .toList();

        final request = server.to(ApiRoutes.chat).single;
        expect(request.headers['authorization'], 'Bearer token-1');
        expect(request.json['spoken'], isTrue);
        expect(request.json['cat']['name'], 'Luna');
        expect((request.json['messages'] as List).map((m) => m['text']), [
          'q1',
          'a1',
          'q2',
        ]);
      },
    );

    test(
      'THE APP NEVER SENDS A PROMPT (the server owns all instructions)',
      () async {
        final (server, client, _) = await setup();
        server.routes[ApiRoutes.chat] = (r) => sse([
          {'type': 'delta', 'text': 'ok'},
          {'type': 'done'},
        ]);
        server.routes[ApiRoutes.screen] = (r) => ok(
          const HealthScreening(
            urgency: Urgency.monitorAtHome,
            summary: '',
          ).toJson(),
        );
        server.routes[ApiRoutes.studio] = (r) => ok(
          const ContentSuggestion(
            mood: PetMood.sweet,
            captions: [],
            hashtags: [],
          ).toJson(),
        );

        await ask(client, spoken: true).toList();
        await BackendVisionService(client).screen(
          photos: [photo],
          concern: 'x',
          duration: null,
          cat: const CatProfile(name: 'Luna', notes: 'Shy'),
        );
        await BackendContentService(
          client,
        ).suggest(photo: photo, note: 'n', cat: null);

        final aiRequests = server.seen.where(
          (s) => s.path.startsWith('/v1/') && s.path != ApiRoutes.register,
        );
        expect(aiRequests.length, 3);
        for (final r in aiRequests) {
          final text = r.body.toLowerCase();
          expect(text, isNot(contains('system')), reason: r.path);
          expect(text, isNot(contains('prompt')), reason: r.path);
          expect(text, isNot(contains('you are')), reason: r.path);
          expect(text, isNot(contains('instructions')), reason: r.path);
        }
      },
    );

    test('an error event becomes an AiServiceException', () async {
      final (server, client, _) = await setup();
      server.routes[ApiRoutes.chat] = (r) => sse([
        {'type': 'delta', 'text': 'Par'},
        {'type': 'error', 'code': 'provider_error', 'message': 'Overloaded.'},
      ]);
      final pieces = <String>[];
      await expectLater(
        ask(client).forEach(pieces.add),
        failsWith('Overloaded.'),
      );
      expect(pieces, ['Par']); // what arrived is delivered before the error
    });

    test('a reply with no words is an error, not silence', () async {
      final (server, client, _) = await setup();
      server.routes[ApiRoutes.chat] = (r) => sse([
        {'type': 'done'},
      ]);
      expect(ask(client).toList(), throwsA(isA<AiServiceException>()));
    });

    test('heartbeat comment lines are ignored', () async {
      final (server, client, _) = await setup();
      server.routes[ApiRoutes.chat] = (r) => http.StreamedResponse(
        Stream.fromIterable([
          utf8.encode(': ping\n\n'),
          utf8.encode('data: {"type":"delta","text":"Hi"}\n\n'),
          utf8.encode(': ping\n\n'),
          utf8.encode('data: {"type":"done"}\n\n'),
        ]),
        200,
      );
      expect(await ask(client).toList(), ['Hi']);
    });

    test(
      'an event split across network packets (and emoji) still parses',
      () async {
        final (server, client, _) = await setup();
        final bytes = utf8.encode(
          'data: {"type":"delta","text":"Purr 🐱"}\n\ndata: {"type":"done"}\n\n',
        );
        server.routes[ApiRoutes.chat] = (r) => http.StreamedResponse(
          Stream.fromIterable([
            for (var i = 0; i < bytes.length; i += 5)
              bytes.sublist(i, i + 5 > bytes.length ? bytes.length : i + 5),
          ]),
          200,
        );
        expect((await ask(client).toList()).join(), 'Purr 🐱');
      },
    );

    test('401 -> gets a fresh token and retries once, invisibly', () async {
      final (server, client, _) = await setup();
      server.routes[ApiRoutes.chat] = (r) {
        if (r.headers['authorization'] == 'Bearer token-1') {
          return err(401, 'unauthorized', 'Please restart the app.');
        }
        return sse([
          {'type': 'delta', 'text': 'worked'},
          {'type': 'done'},
        ]);
      };
      expect(await ask(client).toList(), ['worked']);
      expect(server.to(ApiRoutes.chat).length, 2);
      expect(server.to(ApiRoutes.register).length, 2);
    });

    test('401 twice gives up with a clear message (no endless loop)', () async {
      final (server, client, _) = await setup();
      server.routes[ApiRoutes.chat] = (r) =>
          err(401, 'unauthorized', 'Please restart the app to sign in again.');
      await expectLater(ask(client).toList(), failsWith(contains('restart')));
      expect(server.to(ApiRoutes.chat).length, 2);
    });

    test('rate-limit and budget messages from the server are shown', () async {
      final (server, client, _) = await setup();
      for (final (status, code, message) in [
        (429, 'rate_limited', 'You are going a little fast.'),
        (429, 'quota_exceeded', 'You have reached today\'s limit.'),
        (503, 'busy', 'The assistant is very busy today.'),
      ]) {
        server.routes[ApiRoutes.chat] = (r) => err(status, code, message);
        await expectLater(ask(client).toList(), failsWith(message));
      }
    });

    test('a non-JSON error page gets a generic message', () async {
      final (server, client, _) = await setup();
      server.routes[ApiRoutes.chat] = (r) => http.StreamedResponse(
        Stream.value(utf8.encode('<html>Bad gateway</html>')),
        502,
      );
      await expectLater(
        ask(client).toList(),
        failsWith(contains('unavailable')),
      );
    });

    test('a network failure is a friendly message', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final flaky = MockClient.streaming((request, body) async {
        if (request.url.path == ApiRoutes.register) {
          return ok({
            'token': 't',
            'expiresAt': DateTime.utc(2027).toIso8601String(),
          });
        }
        throw http.ClientException('connection reset');
      });
      final client = BackendClient(
        BackendSession(baseUrl: baseUrl, prefs: prefs, client: flaky),
      );
      await expectLater(
        ask(client).toList(),
        failsWith(contains('reach the Whiskers service')),
      );
    });

    test('cancelling the stream stops reading (Stop button)', () async {
      final (server, client, _) = await setup();
      final controller = StreamController<List<int>>();
      var cancelled = false;
      controller.onCancel = () => cancelled = true;
      server.routes[ApiRoutes.chat] = (r) =>
          http.StreamedResponse(controller.stream, 200);

      final got = <String>[];
      final sub = ask(client).listen(got.add);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      controller.add(utf8.encode('data: {"type":"delta","text":"A"}\n\n'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(got, ['A']);
      expect(cancelled, isTrue);
    });
  });

  group('BackendVisionService / BackendContentService', () {
    test('screen: sends photos, returns the parsed result', () async {
      final (server, client, _) = await setup();
      server.routes[ApiRoutes.screen] = (r) => ok(
        const HealthScreening(
          urgency: Urgency.emergency,
          summary: 'Go now.',
          seeVetIf: ['always'],
        ).toJson(),
      );

      final result = await BackendVisionService(client).screen(
        photos: [photo, photo],
        concern: 'limping',
        duration: 'A few days',
        cat: const CatProfile(name: 'Luna'),
      );
      expect(result.urgency, Urgency.emergency);

      final body = server.to(ApiRoutes.screen).single.json;
      expect((body['photos'] as List).length, 2);
      expect(base64Decode(body['photos'][0]['data']), [1, 2, 3]);
      expect(body['photos'][0]['mimeType'], 'image/jpeg');
      expect(body['concern'], 'limping');
      expect(body['duration'], 'A few days');
      expect(body['cat']['name'], 'Luna');
    });

    test('studio: returns captions, mood and focus', () async {
      final (server, client, _) = await setup();
      server.routes[ApiRoutes.studio] = (r) => ok(
        const ContentSuggestion(
          mood: PetMood.regal,
          focusX: 0.2,
          focusY: 0.7,
          captions: [CaptionOption(tone: 'funny', text: 'Ha')],
          hashtags: ['catsofinstagram'],
        ).toJson(),
      );

      final s = await BackendContentService(
        client,
      ).suggest(photo: photo, note: 'snow', cat: null);
      expect(s.mood, PetMood.regal);
      expect((s.focusX, s.focusY), (0.2, 0.7));
      expect(s.captions.single.text, 'Ha');
      expect(server.to(ApiRoutes.studio).single.json['note'], 'snow');
    });

    test('server errors surface as friendly messages', () async {
      final (server, client, _) = await setup();
      server.routes[ApiRoutes.screen] = (r) =>
          err(502, 'provider_error', 'The AI service is overloaded.');
      await expectLater(
        BackendVisionService(
          client,
        ).screen(photos: [photo], concern: '', duration: null, cat: null),
        failsWith('The AI service is overloaded.'),
      );
    });

    test('a garbled success body is an error, not a crash', () async {
      final (server, client, _) = await setup();
      server.routes[ApiRoutes.studio] = (r) =>
          http.StreamedResponse(Stream.value(utf8.encode('not json')), 200);
      await expectLater(
        BackendContentService(
          client,
        ).suggest(photo: photo, note: '', cat: null),
        throwsA(isA<AiServiceException>()),
      );
    });
  });

  group('AppServices.fromConfig (which mode?)', () {
    Future<SharedPreferences> prefs() async {
      SharedPreferences.setMockInitialValues({});
      return SharedPreferences.getInstance();
    }

    test(
      'a backend URL wins, even when provider keys are also present',
      () async {
        final s = AppServices.fromConfig(
          prefs: await prefs(),
          backendUrl: 'http://localhost:8080',
          providers: const ProviderConfig(geminiApiKey: 'secret-key'),
          releaseMode: false,
        );
        expect(s.mode, AiMode.backend);
        expect(s.chat, isA<BackendAiService>());
        expect(s.vision, isA<BackendVisionService>());
        expect(s.content, isA<BackendContentService>());
      },
    );

    test('no backend, a Gemini key -> direct (Gemini preferred)', () {
      final s = AppServices.fromConfig(
        backendUrl: '',
        providers: const ProviderConfig(
          geminiApiKey: 'g',
          anthropicApiKey: 'a',
        ),
      );
      expect(s.mode, AiMode.direct);
      expect(s.chat, isA<GeminiAiService>());
      expect(s.vision, isA<GeminiVisionService>());
    });

    test('no backend, only a Claude key -> direct Claude', () {
      final s = AppServices.fromConfig(
        backendUrl: '',
        providers: const ProviderConfig(anthropicApiKey: 'a'),
      );
      expect(s.mode, AiMode.direct);
      expect(s.chat, isA<ClaudeAiService>());
    });

    test('nothing configured -> demo mode', () {
      final s = AppServices.fromConfig(
        backendUrl: '',
        providers: const ProviderConfig(),
      );
      expect(s.mode, AiMode.demo);
      expect(s.chat, isA<MockAiService>());
      expect(s.vision, isA<MockVisionService>());
      expect(s.content, isA<MockContentService>());
    });

    test('a bad backend URL is reported, not ignored', () {
      expect(
        () => AppServices.fromConfig(
          backendUrl: 'not a url',
          providers: const ProviderConfig(),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('parseBackendUrl', () {
    test('accepts https and keeps only scheme, host and port', () {
      expect(
        parseBackendUrl(
          'https://api.example.com/some/path?x=1',
          releaseMode: true,
        ).toString(),
        'https://api.example.com',
      );
      expect(
        parseBackendUrl(
          'http://localhost:8080/',
          releaseMode: false,
        ).toString(),
        'http://localhost:8080',
      );
    });

    test(
      'plain http is refused in a release build, allowed in development',
      () {
        for (final url in ['http://api.example.com', 'http://localhost:8080']) {
          expect(
            () => parseBackendUrl(url, releaseMode: true),
            throwsA(isA<FormatException>()),
            reason: url,
          );
        }
        expect(
          parseBackendUrl('http://10.0.2.2:8080', releaseMode: false).host,
          '10.0.2.2',
        );
      },
    );

    test('rubbish is refused', () {
      for (final bad in [
        '',
        'localhost:8080',
        'ftp://example.com',
        'http://',
        '   ',
      ]) {
        expect(
          () => parseBackendUrl(bad, releaseMode: false),
          throwsA(isA<FormatException>()),
          reason: '"$bad"',
        );
      }
    });
  });
}
