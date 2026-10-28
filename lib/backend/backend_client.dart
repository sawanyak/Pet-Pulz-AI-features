import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:pet_core/pet_core.dart';

import 'backend_session.dart';

/// Sends requests to the backend: adds the login token, retries once with a
/// fresh token if the server says 401, and turns every failure into an
/// [AiServiceException] carrying a message that is safe to show.
class BackendClient {
  BackendClient(this.session);

  final BackendSession session;

  /// Give up if nothing at all (not even a heartbeat) arrives for this long.
  static const _idleTimeout = Duration(seconds: 60);
  static const _oneShotTimeout = Duration(seconds: 90);

  /// A normal request/response call (health check, screener, studio).
  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    for (var attempt = 0; ; attempt++) {
      final token = await session.token();
      final http.Response response;
      try {
        response = await session.client
            .post(
              session.url(path),
              headers: {
                'content-type': 'application/json',
                'authorization': 'Bearer $token',
              },
              body: jsonEncode(body),
            )
            .timeout(_oneShotTimeout);
      } on Object catch (e) {
        throw _networkError(e);
      }

      if (response.statusCode == 401 && attempt == 0) {
        await session.reset(); // token expired or server secret changed
        continue;
      }
      if (response.statusCode != 200) throw _errorFrom(response);
      try {
        return jsonDecode(utf8.decode(response.bodyBytes))
            as Map<String, dynamic>;
      } on Object {
        throw AiServiceException(_unexpected);
      }
    }
  }

  /// A streamed call (chat): events as they arrive.
  ///
  /// Written with a controller and held subscriptions (not `async*`) so that
  /// cancelling the returned stream (the Stop button, leaving the screen)
  /// closes the network connection AT ONCE.
  Stream<ChatEvent> postEvents(String path, Map<String, dynamic> body) {
    late final StreamController<ChatEvent> out;
    StreamSubscription<ChatEvent>? inner;
    var cancelled = false;

    void fail(Object e) {
      if (cancelled || out.isClosed) return;
      out.addError(e is AiServiceException ? e : _networkError(e));
      out.close();
    }

    Future<void> start() async {
      try {
        for (var attempt = 0; ; attempt++) {
          final token = await session.token();
          if (cancelled) return;

          final request = http.Request('POST', session.url(path))
            ..headers.addAll({
              'content-type': 'application/json',
              'authorization': 'Bearer $token',
              'accept': 'text/event-stream',
            })
            ..body = jsonEncode(body);

          final http.StreamedResponse response;
          try {
            response = await session.client.send(request).timeout(_idleTimeout);
          } on Object catch (e) {
            throw _networkError(e);
          }
          if (cancelled) {
            unawaited(response.stream.listen(null).cancel());
            return;
          }

          if (response.statusCode == 401 && attempt == 0) {
            await response.stream.drain<void>();
            await session.reset(); // token expired or server secret changed
            continue;
          }
          if (response.statusCode != 200) {
            throw _errorFrom(await http.Response.fromStream(response));
          }

          // The timeout sits on the RAW bytes, so the server's heartbeat
          // lines (which carry no event) also count as "still alive".
          inner = sseData(response.stream.timeout(_idleTimeout))
              .map(
                (payload) => ChatEvent.fromJson(
                  jsonDecode(payload) as Map<String, dynamic>,
                ),
              )
              .listen(
                out.add,
                onError: (Object e) {
                  fail(e);
                  inner?.cancel();
                },
                onDone: () {
                  if (!out.isClosed) out.close();
                },
                cancelOnError: true,
              );
          return;
        }
      } on Object catch (e) {
        fail(e);
      }
    }

    out = StreamController<ChatEvent>(
      onListen: () => unawaited(start()),
      onCancel: () {
        cancelled = true;
        return inner?.cancel();
      },
    );
    return out.stream;
  }

  // ---------------------------------------------------------------- errors

  static const _unexpected =
      'The Whiskers service sent an unexpected answer. Please try again.';

  AiServiceException _networkError(Object e) {
    if (e is AiServiceException) return e;
    if (e is TimeoutException) {
      return AiServiceException('That took too long. Please try again.');
    }
    if (e is SocketException || e is http.ClientException) {
      return AiServiceException(
        'Couldn\'t reach the Whiskers service. Check your connection and try '
        'again.',
      );
    }
    return AiServiceException(_unexpected);
  }

  /// The server's own message when it sent one, otherwise a generic one.
  AiServiceException _errorFrom(http.Response r) {
    try {
      final json = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final message = (json['error'] as Map?)?['message'];
      if (message is String && message.isNotEmpty) {
        return AiServiceException(message);
      }
    } on Object {
      // fall through to the generic messages
    }
    return AiServiceException(switch (r.statusCode) {
      401 => 'Please restart the app to sign in again.',
      413 => 'That is too large to send. Try fewer or smaller photos.',
      429 => 'You are going a little fast. Please wait a moment.',
      >= 500 =>
        'The Whiskers service is unavailable right now. Try again '
            'shortly.',
      _ => 'Something went wrong (error ${r.statusCode}).',
    });
  }
}
