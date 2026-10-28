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

/// Talks to Google Gemini through the Generative Language REST API, with
/// streaming.
///
/// Same contract as [ClaudeAiService]; only the JSON shape differs:
///   * hidden instructions go in `system_instruction`
///   * messages are called `contents`, with roles `user` and `model`
///   * we call `:streamGenerateContent?alt=sse`, and every event is a normal
///     response holding the next piece of text in
///     `candidates[0].content.parts[]`
///
/// SECURITY NOTE: same as Claude - fine for development, but move this call
/// to a backend before publishing the app.
class GeminiAiService implements AiService {
  GeminiAiService({http.Client? client, this.config = const ProviderConfig()})
    : _client = client ?? http.Client();

  final ProviderConfig config;

  final http.Client _client;

  static const _idleTimeout = Duration(seconds: 60);

  @override
  Stream<String> replyStream(
    List<ChatMessage> history, {
    required CatProfile? cat,
    required bool spoken,
  }) async* {
    final endpoint = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '${config.geminiModel}:streamGenerateContent?alt=sse',
    );

    final contents = [
      for (final m in history)
        if (!m.isError)
          {
            'role': m.isUser ? 'user' : 'model',
            'parts': [
              {'text': m.text},
            ],
          },
    ];

    final request = http.Request('POST', endpoint)
      ..headers.addAll({
        'content-type': 'application/json',
        // Sent as a header (not in the URL) so it can't leak in logs.
        'x-goog-api-key': config.geminiApiKey,
      })
      ..body = jsonEncode({
        'system_instruction': {
          'parts': [
            {'text': buildSystemPrompt(cat, spoken: spoken)},
          ],
        },
        'contents': contents,
        'generationConfig': {'maxOutputTokens': 1024},
      });

    var emitted = false;
    String? blockReason;
    try {
      final response = await _client.send(request).timeout(_idleTimeout);

      if (response.statusCode != 200) {
        final body = await http.Response.fromStream(response);
        throw AiServiceException(_friendlyError(body.statusCode, body.body));
      }

      await for (final data in sseData(response.stream).timeout(_idleTimeout)) {
        final chunk = jsonDecode(data) as Map<String, dynamic>;

        // A safety filter can block the answer; Gemini then explains why.
        blockReason ??= chunk['promptFeedback']?['blockReason'] as String?;

        final candidates = chunk['candidates'] as List?;
        if (candidates == null || candidates.isEmpty) continue;

        final parts =
            (candidates.first['content']?['parts'] as List?) ?? const [];
        for (final part in parts) {
          final text = (part as Map<String, dynamic>)['text'] as String?;
          if (text != null && text.isNotEmpty) {
            emitted = true;
            yield text;
          }
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
      throw AiServiceException(
        blockReason != null
            ? 'The assistant couldn\'t answer that. Try rephrasing your question.'
            : 'The assistant sent an empty reply.',
      );
    }
  }

  String _friendlyError(int statusCode, String body) {
    switch (statusCode) {
      // Gemini reports an invalid key as 400 (API_KEY_INVALID), not 401.
      case 400:
        return body.contains('API_KEY_INVALID')
            ? 'The API key was rejected. Check GEMINI_API_KEY.'
            : 'The request was rejected (error 400).';
      case 403:
        return 'This API key isn\'t allowed to use that model.';
      case 404:
        return 'Model "${config.geminiModel}" was not found. '
            'Check GEMINI_MODEL.';
      case 429:
        return 'Too many requests right now. Please wait a moment.';
      case 503:
        return 'The AI service is overloaded. Please try again shortly.';
      default:
        return 'Something went wrong (error $statusCode).';
    }
  }
}
