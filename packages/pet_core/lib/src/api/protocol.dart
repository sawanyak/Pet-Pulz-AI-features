import 'dart:convert';
import 'dart:typed_data';

import '../models/cat_profile.dart';
import '../models/chat_message.dart';

/// THE CONTRACT between the app and the backend server.
///
/// Both sides import this file, so a request the app builds is by
/// construction one the server can read, and the server can enforce the
/// limits below without the app having to agree in a separate place.
///
/// SECURITY IDEA: the app never sends prompts. It sends plain data (the
/// conversation, the cat profile, photos) and the server builds the
/// instructions itself. If the server accepted a prompt from the app, anyone
/// who found its address could use it as a free, general-purpose AI.

/// Size limits, enforced by the server.
abstract final class ApiLimits {
  static const maxMessages = 40;
  static const maxMessageChars = 8000;
  static const maxTotalChars = 60000;

  static const maxPhotos = 3;
  static const maxPhotoBytes = 4 * 1024 * 1024; // after decoding base64
  static const maxConcernChars = 300;
  static const maxDurationChars = 40;
  static const maxNoteChars = 120;

  /// Whole request body. 3 photos of 4 MB become ~16 MB of base64 text.
  static const maxBodyBytes = 17 * 1024 * 1024;

  static const photoMimeTypes = {
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
  };
}

/// Paths and header names.
abstract final class ApiRoutes {
  static const health = '/health';
  static const register = '/v1/register';
  static const chat = '/v1/chat';
  static const screen = '/v1/screen';
  static const studio = '/v1/studio';
}

/// Thrown when a request breaks a rule. [message] is safe to show to a user.
class RequestValidationException implements Exception {
  RequestValidationException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Error codes the server puts in its error responses.
abstract final class ApiErrorCode {
  static const badRequest = 'bad_request';
  static const unauthorized = 'unauthorized';
  static const rateLimited = 'rate_limited';
  static const quotaExceeded = 'quota_exceeded';
  static const busy = 'busy'; // the whole service is at its daily budget
  static const providerError = 'provider_error';
  static const internal = 'internal';
}

/// `{"error": {"code": ..., "message": ...}}`
Map<String, dynamic> errorJson(String code, String message) => {
  'error': {'code': code, 'message': message},
};

// ------------------------------------------------------------------ helpers

Map<String, dynamic> _asMap(Object? json, String what) {
  if (json is! Map) {
    throw RequestValidationException('$what must be an object.');
  }
  return json.cast<String, dynamic>();
}

String _text(Object? v, String name, int max, {bool required = false}) {
  if (v == null) {
    if (required) throw RequestValidationException('"$name" is required.');
    return '';
  }
  if (v is! String) throw RequestValidationException('"$name" must be text.');
  if (v.length > max) {
    throw RequestValidationException('"$name" is too long (max $max).');
  }
  if (required && v.trim().isEmpty) {
    throw RequestValidationException('"$name" must not be empty.');
  }
  return v;
}

CatProfile? _cat(Object? v) {
  if (v == null) return null;
  final profile = CatProfile.fromJson(_asMap(v, '"cat"'));
  return profile.name.trim().isEmpty ? null : profile;
}

// -------------------------------------------------------------------- chat

/// POST /v1/chat
class ChatRequest {
  ChatRequest({required this.messages, this.cat, this.spoken = false});

  final List<ChatMessage> messages;
  final CatProfile? cat;

  /// The answer will be read aloud: ask for short, plain replies.
  final bool spoken;

  Map<String, dynamic> toJson() => {
    'messages': [
      for (final m in messages) {'role': m.role.name, 'text': m.text},
    ],
    if (cat != null) 'cat': cat!.toJson(),
    'spoken': spoken,
  };

  factory ChatRequest.fromJson(Object? json) {
    final map = _asMap(json, 'The request');
    final raw = map['messages'];
    if (raw is! List || raw.isEmpty) {
      throw RequestValidationException('"messages" must be a non-empty list.');
    }
    if (raw.length > ApiLimits.maxMessages) {
      throw RequestValidationException(
        'Too many messages (max ${ApiLimits.maxMessages}).',
      );
    }

    final now = DateTime.now();
    var total = 0;
    final messages = <ChatMessage>[];
    for (final item in raw) {
      final m = _asMap(item, 'Each message');
      final role = m['role'];
      if (role != 'user' && role != 'assistant') {
        throw RequestValidationException(
          'A message role must be "user" or "assistant".',
        );
      }
      final text = _text(
        m['text'],
        'text',
        ApiLimits.maxMessageChars,
        required: true,
      );
      total += text.length;
      messages.add(
        ChatMessage(
          role: role == 'user' ? ChatRole.user : ChatRole.assistant,
          text: text,
          timestamp: now,
        ),
      );
    }
    if (total > ApiLimits.maxTotalChars) {
      throw RequestValidationException('The conversation is too long.');
    }
    // Claude rejects a conversation that starts with, or ends on, the
    // assistant. Catch it here with a clear message.
    if (!messages.first.isUser || !messages.last.isUser) {
      throw RequestValidationException(
        'The conversation must start and end with a "user" message.',
      );
    }

    return ChatRequest(
      messages: messages,
      cat: _cat(map['cat']),
      spoken: map['spoken'] == true,
    );
  }
}

/// One line of the streamed chat response (sent as a Server-Sent Event).
sealed class ChatEvent {
  const ChatEvent();

  Map<String, dynamic> toJson();

  factory ChatEvent.fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'delta':
        return ChatDelta((json['text'] as String?) ?? '');
      case 'error':
        return ChatError(
          (json['code'] as String?) ?? ApiErrorCode.internal,
          (json['message'] as String?) ?? 'Something went wrong.',
        );
      case 'done':
        return const ChatDone();
    }
    return const ChatDelta(''); // unknown event: ignore
  }
}

class ChatDelta extends ChatEvent {
  const ChatDelta(this.text);
  final String text;

  @override
  Map<String, dynamic> toJson() => {'type': 'delta', 'text': text};
}

class ChatError extends ChatEvent {
  const ChatError(this.code, this.message);
  final String code;
  final String message;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'error',
    'code': code,
    'message': message,
  };
}

class ChatDone extends ChatEvent {
  const ChatDone();

  @override
  Map<String, dynamic> toJson() => {'type': 'done'};
}

// ------------------------------------------------------------------ photos

/// A photo as it travels in JSON: base64 text plus its format.
class WirePhoto {
  const WirePhoto({required this.mimeType, required this.bytes});

  final String mimeType;
  final Uint8List bytes;

  Map<String, dynamic> toJson() => {
    'mimeType': mimeType,
    'data': base64Encode(bytes),
  };

  factory WirePhoto.fromJson(Object? json) {
    final m = _asMap(json, 'Each photo');
    final mime = m['mimeType'];
    if (mime is! String || !ApiLimits.photoMimeTypes.contains(mime)) {
      throw RequestValidationException(
        'Photos must be JPEG, PNG, WebP or GIF.',
      );
    }
    final data = m['data'];
    if (data is! String || data.isEmpty) {
      throw RequestValidationException('A photo has no data.');
    }
    // Reject oversize BEFORE decoding: base64 is 4/3 of the real size.
    if (data.length > ApiLimits.maxPhotoBytes * 4 ~/ 3 + 8) {
      throw RequestValidationException('A photo is too large.');
    }
    final Uint8List bytes;
    try {
      bytes = base64Decode(data);
    } on FormatException {
      throw RequestValidationException('A photo is not valid base64.');
    }
    if (bytes.isEmpty || bytes.length > ApiLimits.maxPhotoBytes) {
      throw RequestValidationException('A photo is too large.');
    }
    return WirePhoto(mimeType: mime, bytes: bytes);
  }
}

// ------------------------------------------------------------------ screen

/// POST /v1/screen  (the photo health check)
class ScreenRequest {
  ScreenRequest({
    required this.photos,
    this.concern = '',
    this.duration,
    this.cat,
  });

  final List<WirePhoto> photos;
  final String concern;
  final String? duration;
  final CatProfile? cat;

  Map<String, dynamic> toJson() => {
    'photos': [for (final p in photos) p.toJson()],
    'concern': concern,
    if (duration != null) 'duration': duration,
    if (cat != null) 'cat': cat!.toJson(),
  };

  factory ScreenRequest.fromJson(Object? json) {
    final map = _asMap(json, 'The request');
    final raw = map['photos'];
    if (raw is! List || raw.isEmpty) {
      throw RequestValidationException('Add at least one photo.');
    }
    if (raw.length > ApiLimits.maxPhotos) {
      throw RequestValidationException(
        'Too many photos (max ${ApiLimits.maxPhotos}).',
      );
    }
    final duration = _text(
      map['duration'],
      'duration',
      ApiLimits.maxDurationChars,
    );
    return ScreenRequest(
      photos: [for (final p in raw) WirePhoto.fromJson(p)],
      concern: _text(map['concern'], 'concern', ApiLimits.maxConcernChars),
      duration: duration.isEmpty ? null : duration,
      cat: _cat(map['cat']),
    );
  }
}

// ------------------------------------------------------------------ studio

/// POST /v1/studio  (captions, hashtags, mood and focus for one photo)
class StudioRequest {
  StudioRequest({required this.photo, this.note = '', this.cat});

  final WirePhoto photo;
  final String note;
  final CatProfile? cat;

  Map<String, dynamic> toJson() => {
    'photo': photo.toJson(),
    'note': note,
    if (cat != null) 'cat': cat!.toJson(),
  };

  factory StudioRequest.fromJson(Object? json) {
    final map = _asMap(json, 'The request');
    if (map['photo'] == null) {
      throw RequestValidationException('Add a photo.');
    }
    return StudioRequest(
      photo: WirePhoto.fromJson(map['photo']),
      note: _text(map['note'], 'note', ApiLimits.maxNoteChars),
      cat: _cat(map['cat']),
    );
  }
}
