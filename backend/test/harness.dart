import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:pet_core/pet_core.dart';
import 'package:shelf/shelf.dart';
import 'package:whiskers_backend/whiskers_backend.dart';

const testSecret = 'test-secret-that-is-at-least-32-characters-long!!';
const testProviderKey = 'sk-test-PROVIDER-KEY-must-never-leak';

/// A chat AI whose replies and failures the test controls.
class FakeChat implements AiService {
  List<String> pieces = ['Hello ', 'there'];
  Object? failWith;
  Stream<String>? custom; // takes priority over pieces
  bool cancelled = false;

  List<ChatMessage>? lastHistory;
  CatProfile? lastCat;
  bool? lastSpoken;
  int calls = 0;

  @override
  Stream<String> replyStream(
    List<ChatMessage> history, {
    required CatProfile? cat,
    required bool spoken,
  }) {
    calls++;
    lastHistory = history;
    lastCat = cat;
    lastSpoken = spoken;
    if (custom != null) return custom!;
    return () async* {
      try {
        for (final p in pieces) {
          yield p;
        }
        if (failWith != null) throw failWith!;
      } finally {
        cancelled = true;
      }
    }();
  }
}

class FakeVision implements VisionService {
  HealthScreening result = const HealthScreening(
    urgency: Urgency.seeVetSoon,
    summary: 'Red patch.',
    observations: ['red'],
    seeVetIf: ['worse'],
  );
  Object? failWith;
  Completer<HealthScreening>? gate;
  int calls = 0;
  List<ScreenerPhoto>? lastPhotos;
  String? lastConcern, lastDuration;
  CatProfile? lastCat;

  @override
  Future<HealthScreening> screen({
    required List<ScreenerPhoto> photos,
    required String concern,
    required String? duration,
    required CatProfile? cat,
  }) async {
    calls++;
    lastPhotos = photos;
    lastConcern = concern;
    lastDuration = duration;
    lastCat = cat;
    if (failWith != null) throw failWith!;
    if (gate != null) return gate!.future;
    return result;
  }
}

class FakeContent implements ContentService {
  ContentSuggestion result = const ContentSuggestion(
    mood: PetMood.cozy,
    focusX: 0.3,
    focusY: 0.6,
    subject: 'a cat',
    captions: [CaptionOption(tone: 'funny', text: 'Ha')],
    hashtags: ['catsofinstagram'],
  );
  Object? failWith;
  int calls = 0;
  String? lastNote;
  ScreenerPhoto? lastPhoto;

  @override
  Future<ContentSuggestion> suggest({
    required ScreenerPhoto photo,
    required String note,
    required CatProfile? cat,
  }) async {
    calls++;
    lastNote = note;
    lastPhoto = photo;
    if (failWith != null) throw failWith!;
    return result;
  }
}

ServerConfig testConfig({
  int chatPerMinute = 100,
  int chatPerDay = 1000,
  int visionPerMinute = 100,
  int visionPerDay = 1000,
  int registerPerHour = 100,
  int dailyCap = 100000,
  int maxConcurrent = 40,
  int trustedHops = 0,
  Duration tokenTtl = const Duration(days: 30),
}) => ServerConfig(
  tokenSecret: testSecret,
  providers: const ProviderConfig(geminiApiKey: testProviderKey),
  provider: ProviderChoice.gemini,
  tokenTtl: tokenTtl,
  chatPerMinute: chatPerMinute,
  chatPerDay: chatPerDay,
  visionPerMinute: visionPerMinute,
  visionPerDay: visionPerDay,
  registerPerHourPerIp: registerPerHour,
  dailyRequestCap: dailyCap,
  maxConcurrentProviderCalls: maxConcurrent,
  trustedProxyHops: trustedHops,
);

/// A whole server plus a controllable clock and a capture of its log.
class Harness {
  Harness({ServerConfig? config, DateTime? start})
    : config = config ?? testConfig(),
      time = start ?? DateTime.utc(2026, 9, 30, 12) {
    handler = buildHandler(
      config: this.config,
      services: Services(chat: chat, vision: vision, content: content),
      clock: () => time,
      log: logs.add,
      heartbeat: const Duration(hours: 1), // effectively off in tests
    );
  }

  final ServerConfig config;
  DateTime time;
  final chat = FakeChat();
  final vision = FakeVision();
  final content = FakeContent();
  final logs = <Map<String, Object?>>[];
  late final Handler handler;

  void advance(Duration d) => time = time.add(d);

  Future<Response> send(
    String method,
    String path, {
    Object? body,
    Stream<List<int>>? bodyStream,
    String? token,
    Map<String, String>? headers,
    bool rawBody = false,
  }) {
    final h = <String, String>{
      'authorization': ?(token == null ? null : 'Bearer $token'),
      'content-type': ?(body != null || bodyStream != null
          ? 'application/json'
          : null),
      ...?headers,
    };
    final Object? payload =
        bodyStream ??
        (body == null ? null : (rawBody ? body as String : jsonEncode(body)));
    return Future.value(
      handler(
        Request(
          method,
          Uri.parse('http://localhost$path'),
          headers: h,
          body: payload,
        ),
      ),
    );
  }

  /// Registers a new anonymous install and returns its token.
  Future<String> register({Map<String, String>? headers, String? token}) async {
    final r = await send(
      'POST',
      ApiRoutes.register,
      headers: headers,
      token: token,
    );
    expectOk(r);
    final json = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    return json['token'] as String;
  }

  TokenService get tokenService =>
      TokenService(secret: testSecret, ttl: config.tokenTtl, clock: () => time);
}

void expectOk(Response r) {
  if (r.statusCode != 200) {
    throw StateError('Expected 200 but got ${r.statusCode}');
  }
}

Map<String, dynamic> chatBody({
  List<Map<String, String>>? messages,
  Map<String, dynamic>? cat,
  bool spoken = false,
}) => {
  'messages':
      messages ??
      [
        {'role': 'user', 'text': 'hello'},
      ],
  'cat': ?cat,
  'spoken': spoken,
};

Map<String, dynamic> photoBody([List<int> bytes = const [1, 2, 3]]) => {
  'mimeType': 'image/jpeg',
  'data': base64Encode(Uint8List.fromList(bytes)),
};

/// Parses an SSE body into its events (ignoring comment/heartbeat lines).
List<ChatEvent> parseEvents(String body) => [
  for (final line in body.split('\n'))
    if (line.startsWith('data:'))
      ChatEvent.fromJson(
        jsonDecode(line.substring(5).trim()) as Map<String, dynamic>,
      ),
];

Future<Map<String, dynamic>> jsonOf(Response r) async =>
    jsonDecode(await r.readAsString()) as Map<String, dynamic>;
