import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pet_core/pet_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend/backend_client.dart';
import 'backend/backend_services.dart';
import 'backend/backend_session.dart';
import 'config.dart';

/// How the app reaches the AI.
enum AiMode {
  /// Through the Whiskers backend server. The right choice for a real app:
  /// no provider key is ever inside the app.
  backend,

  /// Straight to Claude / Gemini with keys from `.env`. Fine for development
  /// on your own machine; NOT safe to ship, because the keys are inside the
  /// app.
  direct,

  /// Fake answers, no network. Used when nothing is configured.
  demo,
}

/// The three AI abilities the screens use, plus which mode provides them.
class AppServices {
  const AppServices({
    required this.mode,
    required this.chat,
    required this.vision,
    required this.content,
  });

  final AiMode mode;
  final AiService chat;
  final VisionService vision;
  final ContentService content;

  /// Picks the mode from the settings:
  ///   BACKEND_URL set        -> [AiMode.backend]
  ///   else a provider key    -> [AiMode.direct]
  ///   else                   -> [AiMode.demo]
  ///
  /// [prefs] is needed (only) for backend mode, to remember the login token.
  factory AppServices.fromConfig({
    SharedPreferences? prefs,
    http.Client? client,
    String? backendUrl,
    ProviderConfig? providers,
    bool? releaseMode,
  }) {
    final url = (backendUrl ?? AppConfig.backendUrl).trim();
    final keys = providers ?? AppConfig.provider;

    if (url.isNotEmpty) {
      final base = parseBackendUrl(
        url,
        releaseMode: releaseMode ?? kReleaseMode,
      );
      if (prefs == null) {
        throw StateError('Backend mode needs SharedPreferences.');
      }
      final backend = BackendClient(
        BackendSession(baseUrl: base, prefs: prefs, client: client),
      );
      return AppServices(
        mode: AiMode.backend,
        chat: BackendAiService(backend),
        vision: BackendVisionService(backend),
        content: BackendContentService(backend),
      );
    }

    if (keys.hasGemini) {
      return AppServices(
        mode: AiMode.direct,
        chat: GeminiAiService(config: keys, client: client),
        vision: GeminiVisionService(config: keys, client: client),
        content: AiContentService(
          GeminiStructuredVision(config: keys, client: client),
        ),
      );
    }
    if (keys.hasAnthropic) {
      return AppServices(
        mode: AiMode.direct,
        chat: ClaudeAiService(config: keys, client: client),
        vision: ClaudeVisionService(config: keys, client: client),
        content: AiContentService(
          ClaudeStructuredVision(config: keys, client: client),
        ),
      );
    }

    return AppServices(
      mode: AiMode.demo,
      chat: MockAiService(),
      vision: MockVisionService(),
      content: MockContentService(),
    );
  }
}

/// Validates BACKEND_URL. In a release build the connection must be
/// encrypted (https): otherwise the login token and the owner's photos and
/// chat would cross the network in plain text. Plain http is allowed for
/// your own machine while developing (localhost and the Android emulator's
/// alias for it).
Uri parseBackendUrl(String raw, {required bool releaseMode}) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    throw FormatException('BACKEND_URL is not a valid http(s) address: $raw');
  }
  if (uri.scheme == 'http' && releaseMode) {
    throw FormatException('BACKEND_URL must use https in a release build.');
  }
  // Keep only scheme + host + port: paths are added per request.
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
  );
}
