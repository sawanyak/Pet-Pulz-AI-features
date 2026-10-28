import 'dart:async';

import 'package:pet_core/pet_core.dart';

import 'backend_client.dart';

/// Chat through the backend. The app sends the conversation, the cat profile
/// and the spoken flag; the SERVER builds the instructions and holds the key.
class BackendAiService implements AiService {
  BackendAiService(this._client);

  final BackendClient _client;

  @override
  Stream<String> replyStream(
    List<ChatMessage> history, {
    required CatProfile? cat,
    required bool spoken,
  }) {
    final request = ChatRequest(
      messages: [
        for (final m in history)
          if (!m.isError) m,
      ],
      cat: cat,
      spoken: spoken,
    );

    var gotAnything = false;
    var finished = false;

    // A stream TRANSFORMER (not an `async*` generator) so that cancelling
    // it reaches the network connection immediately.
    return _client
        .postEvents(ApiRoutes.chat, request.toJson())
        .transform(
          StreamTransformer<ChatEvent, String>.fromHandlers(
            handleData: (event, sink) {
              if (finished) return;
              switch (event) {
                case ChatDelta(:final text):
                  if (text.isEmpty) return;
                  gotAnything = true;
                  sink.add(text);
                case ChatError(:final message):
                  finished = true;
                  sink.addError(AiServiceException(message));
                  sink.close();
                case ChatDone():
                  finished = true;
                  if (!gotAnything) {
                    sink.addError(
                      AiServiceException('The assistant sent an empty reply.'),
                    );
                  }
                  sink.close();
              }
            },
            handleDone: (sink) {
              // The connection ended without a "done" event.
              if (!finished && !gotAnything) {
                sink.addError(
                  AiServiceException('The assistant sent an empty reply.'),
                );
              }
              if (!finished) sink.close();
            },
          ),
        );
  }
}

/// The photo health check through the backend.
class BackendVisionService implements VisionService {
  BackendVisionService(this._client);

  final BackendClient _client;

  @override
  Future<HealthScreening> screen({
    required List<ScreenerPhoto> photos,
    required String concern,
    required String? duration,
    required CatProfile? cat,
  }) async {
    final request = ScreenRequest(
      photos: [
        for (final p in photos) WirePhoto(mimeType: p.mimeType, bytes: p.bytes),
      ],
      concern: concern,
      duration: duration,
      cat: cat,
    );
    final json = await _client.postJson(ApiRoutes.screen, request.toJson());
    return HealthScreening.fromJson(json);
  }
}

/// Captions, hashtags, mood and focus point through the backend.
class BackendContentService implements ContentService {
  BackendContentService(this._client);

  final BackendClient _client;

  @override
  Future<ContentSuggestion> suggest({
    required ScreenerPhoto photo,
    required String note,
    required CatProfile? cat,
  }) async {
    final request = StudioRequest(
      photo: WirePhoto(mimeType: photo.mimeType, bytes: photo.bytes),
      note: note,
      cat: cat,
    );
    final json = await _client.postJson(ApiRoutes.studio, request.toJson());
    return ContentSuggestion.fromJson(json);
  }
}
