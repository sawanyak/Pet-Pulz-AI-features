import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:pet_core/pet_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'config.dart';
import 'rate_limit.dart';
import 'tokens.dart';

/// The three AI abilities the server offers, as interfaces so tests can
/// substitute fakes for the real Claude / Gemini clients.
class Services {
  const Services({
    required this.chat,
    required this.vision,
    required this.content,
  });

  final AiService chat;
  final VisionService vision;
  final ContentService content;
}

/// The real services for the configured provider.
Services servicesFromConfig(ServerConfig c, {http.Client? client}) {
  switch (c.provider) {
    case ProviderChoice.gemini:
      return Services(
        chat: GeminiAiService(config: c.providers, client: client),
        vision: GeminiVisionService(config: c.providers, client: client),
        content: AiContentService(
          GeminiStructuredVision(config: c.providers, client: client),
        ),
      );
    case ProviderChoice.anthropic:
      return Services(
        chat: ClaudeAiService(config: c.providers, client: client),
        vision: ClaudeVisionService(config: c.providers, client: client),
        content: AiContentService(
          ClaudeStructuredVision(config: c.providers, client: client),
        ),
      );
  }
}

/// Receives one structured log entry per request. NEVER put message text,
/// captions or photos in an entry: they are the users' private data.
typedef LogSink = void Function(Map<String, Object?> entry);

void printLog(Map<String, Object?> entry) => stdout.writeln(jsonEncode(entry));

/// Builds the whole server as one request handler.
///
/// Every request goes through, in order:
///   1. request id + timing + logging,
///   2. a safety net that turns any crash into a clean 500,
///   3. routing to an endpoint,
///   4. for /v1/chat, /v1/screen, /v1/studio: the signed token, then the
///      per-minute limit, then validation, then the daily limits and the
///      global budget, and only then the (paid) AI call.
Handler buildHandler({
  required ServerConfig config,
  required Services services,
  DateTime Function()? clock,
  LogSink? log,
  Duration heartbeat = const Duration(seconds: 15),
}) {
  final now = clock ?? DateTime.now;
  final logSink = log ?? printLog;
  final random = Random.secure();

  final tokens = TokenService(
    secret: config.tokenSecret,
    ttl: config.tokenTtl,
    clock: now,
  );

  WindowLimiter minute(int n) =>
      WindowLimiter(limit: n, window: const Duration(minutes: 1), clock: now);
  WindowLimiter day(int n) =>
      WindowLimiter(limit: n, window: const Duration(days: 1), clock: now);

  final chatMinute = minute(config.chatPerMinute);
  final chatDay = day(config.chatPerDay);
  final visionMinute = minute(config.visionPerMinute);
  final visionDay = day(config.visionPerDay);
  final registerLimiter = WindowLimiter(
    limit: config.registerPerHourPerIp,
    window: const Duration(hours: 1),
    clock: now,
  );
  final budget = DailyBudget(cap: config.dailyRequestCap, clock: now);

  var inFlight = 0;
  bool takeSlot() {
    if (inFlight >= config.maxConcurrentProviderCalls) return false;
    inFlight++;
    return true;
  }

  void releaseSlot() => inFlight--;

  // ----------------------------------------------------------- responses

  Response json(int status, Object body, {Map<String, String>? headers}) =>
      Response(
        status,
        body: jsonEncode(body),
        headers: {
          'content-type': 'application/json; charset=utf-8',
          'cache-control': 'no-store',
          ...?headers,
        },
      );

  Response error(
    int status,
    String code,
    String message, {
    Duration? retryAfter,
  }) => json(
    status,
    errorJson(code, message),
    headers: retryAfter == null
        ? null
        : {'retry-after': '${max(1, retryAfter.inSeconds)}'},
  );

  Response blocked(String code, RateDecision d) => error(
    429,
    code,
    'You are going a little fast. Please wait a moment and try again.',
    retryAfter: d.retryAfter,
  );

  // ------------------------------------------------------------- helpers

  String? bearer(Request r) {
    final h = r.headers['authorization'];
    if (h == null || !h.toLowerCase().startsWith('bearer ')) return null;
    return h.substring(7).trim();
  }

  /// The client's IP. Behind a proxy the socket address is the PROXY's, so
  /// we read X-Forwarded-For, but only the entry added by our own trusted
  /// proxy (counting from the right): the left side is whatever the client
  /// chose to send, and trusting it would let anyone fake an IP.
  String clientIp(Request r) {
    final hops = config.trustedProxyHops;
    if (hops > 0) {
      final xff = (r.headers['x-forwarded-for'] ?? '')
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (xff.length >= hops) return xff[xff.length - hops];
    }
    final info = r.context['shelf.io.connection_info'];
    if (info is HttpConnectionInfo) return info.remoteAddress.address;
    return 'unknown';
  }

  String shortHash(String id) =>
      sha256.convert(utf8.encode(id)).toString().substring(0, 10);

  /// Reads and parses the JSON body, refusing anything over [max] bytes
  /// without holding it all in memory.
  Future<Object?> readJson(Request r) async {
    final max = ApiLimits.maxBodyBytes;
    final declared = r.contentLength;
    if (declared != null && declared > max) throw _TooLarge();

    final bytes = BytesBuilder(copy: false);
    await for (final chunk in r.read()) {
      if (bytes.length + chunk.length > max) throw _TooLarge();
      bytes.add(chunk);
    }
    if (bytes.isEmpty) {
      throw RequestValidationException('The request body is empty.');
    }
    try {
      return jsonDecode(utf8.decode(bytes.takeBytes()));
    } on FormatException {
      throw RequestValidationException('The request body is not valid JSON.');
    }
  }

  /// What we tell users about a provider failure. Configuration problems
  /// (wrong key, wrong model) are the OPERATOR's business: the user just
  /// sees "unavailable", and the details go to the server log.
  String publicMessage(AiServiceException e) {
    final m = e.message;
    if (m.contains('API key') ||
        m.contains('_API_KEY') ||
        m.contains('GEMINI_') ||
        m.contains('ANTHROPIC_') ||
        m.startsWith('Model "') ||
        m.contains('isn\'t allowed')) {
      return 'The assistant is temporarily unavailable. Please try again '
          'later.';
    }
    return m;
  }

  // ----------------------------------------------------- endpoint wiring

  /// Wraps an endpoint with token check + per-minute limit.
  Handler protect(
    WindowLimiter perMinute,
    Future<Response> Function(Request, Identity, _Info) handler,
  ) => (Request request) async {
    final info = request.context['info'] as _Info;
    final identity = tokens.verify(bearer(request));
    if (identity == null) {
      return error(
        401,
        ApiErrorCode.unauthorized,
        'Please restart the app to sign in again.',
      );
    }
    info.install = shortHash(identity.installId);

    final decision = perMinute.hit(identity.installId);
    if (!decision.allowed) return blocked(ApiErrorCode.rateLimited, decision);

    return handler(request, identity, info);
  };

  /// The daily limit and the global budget. Returns a response if blocked,
  /// or null if the request may go ahead (and has used its share).
  Response? spend(WindowLimiter perDay, Identity identity) {
    final d = perDay.hit(identity.installId);
    if (!d.allowed) {
      return error(
        429,
        ApiErrorCode.quotaExceeded,
        'You have reached today\'s limit. Please come back tomorrow.',
        retryAfter: d.retryAfter,
      );
    }
    if (!budget.tryTake()) {
      return error(
        503,
        ApiErrorCode.busy,
        'The assistant is very busy today. Please try again tomorrow.',
        retryAfter: budget.untilReset,
      );
    }
    return null;
  }

  /// Runs a one-shot AI call under the concurrency cap and maps failures.
  Future<Response> runVision(
    _Info info,
    Future<Map<String, dynamic>> Function() call,
  ) async {
    if (!takeSlot()) {
      return error(
        503,
        ApiErrorCode.busy,
        'The assistant is busy right now. Please try again in a moment.',
        retryAfter: const Duration(seconds: 5),
      );
    }
    try {
      return json(200, await call());
    } on AiServiceException catch (e) {
      info.note = 'provider: ${e.message}';
      return error(502, ApiErrorCode.providerError, publicMessage(e));
    } finally {
      releaseSlot();
    }
  }

  // ------------------------------------------------------------ handlers

  Future<Response> register(Request request) async {
    final ip = clientIp(request);
    final d = registerLimiter.hit(ip);
    if (!d.allowed) return blocked(ApiErrorCode.rateLimited, d);

    // A still-valid token is renewed (same identity, so quotas carry over);
    // anyone else gets a new anonymous identity.
    final existing = tokens.verify(bearer(request));
    final installId = existing?.installId ?? tokens.newInstallId();
    final issued = tokens.issue(installId);
    return json(200, {
      'token': issued.token,
      'expiresAt': issued.expiresAt.toIso8601String(),
    });
  }

  final chat = protect(chatMinute, (request, identity, info) async {
    final req = ChatRequest.fromJson(await readJson(request));
    final stop = spend(chatDay, identity);
    if (stop != null) return stop;

    List<int> frame(ChatEvent e) =>
        utf8.encode('data: ${jsonEncode(e.toJson())}\n\n');

    // Built from a StreamController and a held subscription (instead of an
    // `async*` generator with `await for`) so that when the phone goes away
    // the AI call is cancelled IMMEDIATELY. A generator that is waiting for
    // the AI's next word cannot be interrupted until that word arrives.
    Stream<List<int>> events() {
      late final StreamController<List<int>> out;
      StreamSubscription<String>? sub;
      var slotTaken = false;

      void release() {
        if (slotTaken) {
          slotTaken = false;
          releaseSlot();
        }
      }

      void fail(String code, String message) {
        if (!out.isClosed) out.add(frame(ChatError(code, message)));
        release();
        if (!out.isClosed) out.close();
      }

      out = StreamController<List<int>>(
        onListen: () {
          // Taken here, when the response is actually being read, so the
          // matching release in onCancel / onDone always runs.
          if (!takeSlot()) {
            fail(
              ApiErrorCode.busy,
              'The assistant is busy right now. Please try again in a moment.',
            );
            return;
          }
          slotTaken = true;
          try {
            sub = services.chat
                .replyStream(req.messages, cat: req.cat, spoken: req.spoken)
                .listen(
                  (piece) => out.add(frame(ChatDelta(piece))),
                  onError: (Object e) {
                    if (e is AiServiceException) {
                      info.note = 'provider: ${e.message}';
                      fail(ApiErrorCode.providerError, publicMessage(e));
                    } else {
                      info.note = 'internal: ${e.runtimeType}';
                      fail(ApiErrorCode.internal, 'Something went wrong.');
                    }
                  },
                  onDone: () {
                    if (!out.isClosed) out.add(frame(const ChatDone()));
                    release();
                    if (!out.isClosed) out.close();
                  },
                  cancelOnError: true,
                );
          } catch (e) {
            info.note = 'internal: ${e.runtimeType}';
            fail(ApiErrorCode.internal, 'Something went wrong.');
          }
        },
        onCancel: () {
          release();
          // Deliberately not awaited: see the comment above.
          unawaited(sub?.cancel() ?? Future<void>.value());
        },
      );
      return out.stream;
    }

    return Response.ok(
      _withHeartbeat(events(), heartbeat),
      headers: {
        'content-type': 'text/event-stream; charset=utf-8',
        'cache-control': 'no-cache, no-transform',
        // Tell proxies (nginx) not to buffer: the point is streaming.
        'x-accel-buffering': 'no',
      },
    );
  });

  final screen = protect(visionMinute, (request, identity, info) async {
    final req = ScreenRequest.fromJson(await readJson(request));
    final stop = spend(visionDay, identity);
    if (stop != null) return stop;

    return runVision(info, () async {
      final result = await services.vision.screen(
        photos: [
          for (final p in req.photos)
            ScreenerPhoto(bytes: p.bytes, mimeType: p.mimeType),
        ],
        concern: req.concern,
        duration: req.duration,
        cat: req.cat,
      );
      return result.toJson();
    });
  });

  final studio = protect(visionMinute, (request, identity, info) async {
    final req = StudioRequest.fromJson(await readJson(request));
    final stop = spend(visionDay, identity);
    if (stop != null) return stop;

    return runVision(info, () async {
      final result = await services.content.suggest(
        photo: ScreenerPhoto(
          bytes: req.photo.bytes,
          mimeType: req.photo.mimeType,
        ),
        note: req.note,
        cat: req.cat,
      );
      return result.toJson();
    });
  });

  final router =
      Router(
          notFoundHandler: (r) =>
              error(404, ApiErrorCode.badRequest, 'Not found.'),
        )
        ..get(ApiRoutes.health, (Request r) => json(200, {'status': 'ok'}))
        ..post(ApiRoutes.register, register)
        ..post(ApiRoutes.chat, chat)
        ..post(ApiRoutes.screen, screen)
        ..post(ApiRoutes.studio, studio);

  // ---------------------------------------------------------- middleware

  /// Adds an id, times the request, writes ONE log line, and converts any
  /// exception into a clean JSON error so nothing internal ever leaks.
  Handler observe(Handler inner) => (Request request) async {
    final info = _Info(
      id: List.generate(
        6,
        (_) => random.nextInt(256),
      ).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
    );
    final watch = Stopwatch()..start();
    final req = request.change(context: {'info': info});

    Response response;
    try {
      response = await inner(req);
    } on RequestValidationException catch (e) {
      response = error(400, ApiErrorCode.badRequest, e.message);
    } on _TooLarge {
      response = error(
        413,
        ApiErrorCode.badRequest,
        'That request is too large.',
      );
    } catch (e) {
      info.note = 'internal: ${e.runtimeType}';
      response = error(500, ApiErrorCode.internal, 'Something went wrong.');
    }

    void writeLog() => logSink({
      'ts': now().toUtc().toIso8601String(),
      'id': info.id,
      'method': request.method,
      'path': request.url.path.isEmpty ? '/' : '/${request.url.path}',
      'status': response.statusCode,
      'ms': watch.elapsedMilliseconds,
      if (info.install != null) 'install': info.install,
      if (info.note != null) 'note': info.note,
    });

    final headers = {'x-request-id': info.id};
    final streaming =
        response.headers['content-type']?.startsWith('text/event-stream') ==
        true;
    if (!streaming) {
      writeLog();
      return response.change(headers: headers);
    }

    // A streamed reply is "finished" only when its body ends (or the client
    // leaves), and errors can happen while streaming. So write the log line
    // then, with the real duration and any note.
    Stream<List<int>> logWhenDone(Stream<List<int>> body) async* {
      try {
        yield* body;
      } finally {
        writeLog();
      }
    }

    return response.change(
      headers: headers,
      body: logWhenDone(response.read()),
    );
  };

  return const Pipeline().addMiddleware(observe).addHandler(router.call);
}

/// Per-request scratch space shared between the middleware and endpoints.
class _Info {
  _Info({required this.id});
  final String id;
  String? install;
  String? note;
}

class _TooLarge implements Exception {}

final _ping = utf8.encode(': ping\n\n');

/// Sends an SSE comment line every [every] while the source is quiet, so
/// proxies and mobile networks do not drop a connection that is merely
/// waiting for the AI's first word. SSE clients ignore comment lines.
Stream<List<int>> _withHeartbeat(Stream<List<int>> source, Duration every) {
  late final StreamController<List<int>> controller;
  StreamSubscription<List<int>>? sub;
  Timer? timer;

  controller = StreamController<List<int>>(
    onListen: () {
      timer = Timer.periodic(every, (_) {
        if (!controller.isClosed) controller.add(_ping);
      });
      sub = source.listen(
        controller.add,
        onError: controller.addError,
        onDone: () {
          timer?.cancel();
          controller.close();
        },
      );
    },
    onCancel: () {
      timer?.cancel();
      // Closing the response also stops the AI call. Not awaited, so a slow
      // upstream can never delay closing the connection.
      unawaited(sub?.cancel() ?? Future<void>.value());
    },
  );
  return controller.stream;
}
