import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../provider_config.dart';
import 'ai_service.dart';
import 'vision_service.dart';

/// "Show the AI some photos and get back a JSON object" - the one piece of
/// plumbing that BOTH the health check and the content studio need.
///
/// Each feature supplies its own instructions, JSON schema and photos; this
/// layer knows only how to talk to a provider (Claude or Gemini), how to
/// force a structured answer, and how to turn network failures into friendly
/// [AiServiceException]s.
abstract class StructuredVision {
  Future<Map<String, dynamic>> run({
    required String system,
    required String userText,
    required List<ScreenerPhoto> photos,
    required Map<String, Object?> schema,
    required String toolName,
    required String toolDescription,
    int maxTokens = 1500,
  });
}

/// Claude: the answer is forced through a tool whose input schema is [schema]
/// (`tool_choice`), so the arguments Claude passes to that tool ARE the JSON.
class ClaudeStructuredVision implements StructuredVision {
  ClaudeStructuredVision({
    http.Client? client,
    this.config = const ProviderConfig(),
  }) : _client = client ?? http.Client();

  final ProviderConfig config;

  final http.Client _client;
  static final _endpoint = Uri.parse('https://api.anthropic.com/v1/messages');

  @override
  Future<Map<String, dynamic>> run({
    required String system,
    required String userText,
    required List<ScreenerPhoto> photos,
    required Map<String, Object?> schema,
    required String toolName,
    required String toolDescription,
    int maxTokens = 1500,
  }) async {
    final body = {
      'model': config.anthropicModel,
      'max_tokens': maxTokens,
      'system': system,
      'tools': [
        {
          'name': toolName,
          'description': toolDescription,
          'input_schema': schema,
        },
      ],
      'tool_choice': {'type': 'tool', 'name': toolName},
      'messages': [
        {
          'role': 'user',
          'content': [
            for (final p in photos)
              {
                'type': 'image',
                'source': {
                  'type': 'base64',
                  'media_type': p.mimeType,
                  'data': base64Encode(p.bytes),
                },
              },
            {'type': 'text', 'text': userText},
          ],
        },
      ],
    };

    final response = await _post(_client, _endpoint, {
      'content-type': 'application/json',
      'x-api-key': config.anthropicApiKey,
      'anthropic-version': '2023-06-01',
    }, body);
    if (response.statusCode != 200) {
      throw AiServiceException(_friendlyError(response.statusCode));
    }

    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    for (final b in (data['content'] as List).cast<Map<String, dynamic>>()) {
      if (b['type'] == 'tool_use' && b['name'] == toolName) {
        return b['input'] as Map<String, dynamic>;
      }
    }
    throw AiServiceException(_unreadable);
  }

  String _friendlyError(int status) {
    switch (status) {
      case 401:
        return 'The API key was rejected. Check ANTHROPIC_API_KEY.';
      case 413:
        return 'The photos are too large. Try fewer or smaller photos.';
      case 429:
        return 'Too many requests right now. Please wait a moment.';
      case 529:
        return 'The AI service is overloaded. Please try again shortly.';
      default:
        return 'Something went wrong (error $status).';
    }
  }
}

/// Gemini: `responseMimeType: application/json` makes it reply with raw
/// JSON; the schema is also spelled out in the instructions.
class GeminiStructuredVision implements StructuredVision {
  GeminiStructuredVision({
    http.Client? client,
    this.config = const ProviderConfig(),
  }) : _client = client ?? http.Client();

  final ProviderConfig config;

  final http.Client _client;

  @override
  Future<Map<String, dynamic>> run({
    required String system,
    required String userText,
    required List<ScreenerPhoto> photos,
    required Map<String, Object?> schema,
    required String toolName,
    required String toolDescription,
    int maxTokens = 1500,
  }) async {
    final endpoint = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '${config.geminiModel}:generateContent',
    );

    final body = {
      'system_instruction': {
        'parts': [
          {
            'text':
                '$system\n'
                'Reply with ONLY a JSON object matching this JSON Schema:\n'
                '${jsonEncode(schema)}',
          },
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            for (final p in photos)
              {
                'inline_data': {
                  'mime_type': p.mimeType,
                  'data': base64Encode(p.bytes),
                },
              },
            {'text': userText},
          ],
        },
      ],
      'generationConfig': {
        'responseMimeType': 'application/json',
        // Gemini's "thinking" tokens share this budget, so leave room.
        'maxOutputTokens': maxTokens < 2048 ? 2048 : maxTokens,
      },
    };

    final response = await _post(_client, endpoint, {
      'content-type': 'application/json',
      'x-goog-api-key': config.geminiApiKey,
    }, body);
    if (response.statusCode != 200) {
      throw AiServiceException(_friendlyError(response));
    }

    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final candidates = data['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw AiServiceException(
        'The assistant couldn\'t use that photo. Try a different one.',
      );
    }
    final parts = (candidates.first['content']?['parts'] as List?) ?? const [];
    final text = parts
        .map((p) => (p as Map<String, dynamic>)['text'] as String? ?? '')
        .join();
    return _decodeJsonObject(text);
  }

  /// Models sometimes wrap JSON in ```json fences or add a stray sentence.
  /// Take everything from the first "{" to the last "}".
  static Map<String, dynamic> _decodeJsonObject(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) throw AiServiceException(_unreadable);
    try {
      return jsonDecode(text.substring(start, end + 1)) as Map<String, dynamic>;
    } on FormatException {
      throw AiServiceException(_unreadable);
    }
  }

  String _friendlyError(http.Response r) {
    switch (r.statusCode) {
      case 400:
        return r.body.contains('API_KEY_INVALID')
            ? 'The API key was rejected. Check GEMINI_API_KEY.'
            : 'The photos were rejected (error 400). Try different ones.';
      case 403:
        return 'This API key isn\'t allowed to use that model.';
      case 404:
        return 'Model "${config.geminiModel}" was not found. '
            'Check GEMINI_MODEL.';
      case 413:
        return 'The photos are too large. Try fewer or smaller photos.';
      case 429:
        return 'Too many requests right now. Please wait a moment.';
      case 503:
        return 'The AI service is overloaded. Please try again shortly.';
      default:
        return 'Something went wrong (error ${r.statusCode}).';
    }
  }
}

const _unreadable = 'I couldn\'t read the result. Please try again.';

/// POST with the same failure handling for both providers.
Future<http.Response> _post(
  http.Client client,
  Uri url,
  Map<String, String> headers,
  Object body,
) async {
  try {
    return await client
        .post(url, headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 90));
  } on SocketException {
    throw AiServiceException(
      'No internet connection. Please check your network and try again.',
    );
  } on http.ClientException {
    throw AiServiceException('The connection was lost. Please try again.');
  } on TimeoutException {
    throw AiServiceException('That took too long. Please try again.');
  }
}
