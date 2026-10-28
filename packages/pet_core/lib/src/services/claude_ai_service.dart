import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/cat_profile.dart';
import '../provider_config.dart';
import '../models/chat_message.dart';
import 'ai_service.dart';
import 'pet_assistant_prompt.dart';
import 'sse.dart';

/// Talks to Claude through Anthropic's Messages API, with streaming.
///
/// HOW IT WORKS: one HTTPS POST containing
///   * `system`   - the hidden instructions (who the AI is, safety rules)
///   * `messages` - the conversation so far, alternating user/assistant
///   * `stream: true` - "send the answer piece by piece"
/// Claude then keeps the connection open and sends events. The ones we care
/// about are `content_block_delta` events carrying a `text_delta` with the
/// next few words.
///
/// SECURITY NOTE: putting an API key inside a mobile app is fine for
/// development, but anyone can extract it from a published app. Before
/// releasing, move this call to your own small backend server.
class ClaudeAiService implements AiService {
  ClaudeAiService({http.Client? client, this.config = const ProviderConfig()})
    : _client = client ?? http.Client();

  final ProviderConfig config;

  final http.Client _client;

  static final _endpoint = Uri.parse('https://api.anthropic.com/v1/messages');
  static const _idleTimeout = Duration(seconds: 60);

  @override
  Stream<String> replyStream(
    List<ChatMessage> history, {
    required CatProfile? cat,
    required bool spoken,
  }) async* {
    // Error bubbles are skipped: they're app notices, not real conversation.
    final messages = [
      for (final m in history)
        if (!m.isError)
          {'role': m.isUser ? 'user' : 'assistant', 'content': m.text},
    ];

    final request = http.Request('POST', _endpoint)
      ..headers.addAll({
        'content-type': 'application/json',
        'x-api-key': config.anthropicApiKey,
        'anthropic-version': '2023-06-01',
      })
      ..body = jsonEncode({
        'model': config.anthropicModel,
        'max_tokens': 1024, // upper limit on the reply length
        'stream': true,
        'system': buildSystemPrompt(cat, spoken: spoken),
        'messages': messages,
      });

    var emitted = false;
    try {
      // `send` (unlike `post`) hands us the response as a live stream.
      final response = await _client.send(request).timeout(_idleTimeout);

      if (response.statusCode != 200) {
        final body = await http.Response.fromStream(response);
        throw AiServiceException(_friendlyError(body.statusCode));
      }

      // `.timeout` on a stream fires if NO data arrives for 60s in a row.
      await for (final data in sseData(response.stream).timeout(_idleTimeout)) {
        final event = jsonDecode(data) as Map<String, dynamic>;
        switch (event['type']) {
          case 'content_block_delta':
            final delta = event['delta'] as Map<String, dynamic>;
            if (delta['type'] == 'text_delta') {
              emitted = true;
              yield delta['text'] as String;
            }
          case 'error':
            // Errors can also arrive mid-stream, after a 200 response.
            throw AiServiceException(
              _friendlyError(
                event['error']?['type'] == 'overloaded_error' ? 529 : 500,
              ),
            );
        }
      }
    } on SocketException {
      throw AiServiceException(
        'No internet connection. Please check your network and try again.',
      );
    } on http.ClientException {
      throw AiServiceException('The connection was lost. Please try again.');
    } on TimeoutException {
      throw AiServiceException('The assistant took too long to respond.');
    }

    if (!emitted) {
      throw AiServiceException('The assistant sent an empty reply.');
    }
  }

  String _friendlyError(int statusCode) {
    switch (statusCode) {
      case 401:
        return 'The API key was rejected. Check ANTHROPIC_API_KEY.';
      case 429:
        return 'Too many requests right now. Please wait a moment.';
      case 529:
        return 'The AI service is overloaded. Please try again shortly.';
      default:
        return 'Something went wrong (error $statusCode).';
    }
  }
}
