import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:pet_core/pet_core.dart';

/// App-wide settings, read from the `.env` file in the project root.
///
/// HOW IT WORKS: `main()` calls `dotenv.load()` once at startup, which reads
/// the `.env` file (bundled as an asset) into `dotenv.env`, a plain
/// map of strings. The getters below look values up in that map.
///
/// If both keys are filled in, Gemini is used. If neither is, the app falls
/// back to a fake "mock" AI so you can still try the UI.
///
/// IMPORTANT: because .env is bundled INSIDE the app, anyone who unpacks a
/// published app can read it. It keeps keys out of your source code and git
/// history, which is great for development, but before release move the AI
/// calls to a backend server that holds the keys.
class AppConfig {
  static String _get(String name, [String fallback = '']) {
    // If .env was never loaded (for example in tests) behave as "no
    // settings" instead of crashing.
    if (!dotenv.isInitialized) return fallback;
    final value = dotenv.maybeGet(name)?.trim();
    return (value == null || value.isEmpty) ? fallback : value;
  }

  static String get geminiApiKey => _get('GEMINI_API_KEY');
  static String get geminiModel => _get('GEMINI_MODEL', 'gemini-2.5-flash');

  static String get anthropicApiKey => _get('ANTHROPIC_API_KEY');
  static String get model => _get('ANTHROPIC_MODEL', 'claude-sonnet-5-5');

  /// Keys and models in the form the shared provider clients expect.
  static ProviderConfig get provider => ProviderConfig(
    geminiApiKey: geminiApiKey,
    geminiModel: geminiModel,
    anthropicApiKey: anthropicApiKey,
    anthropicModel: model,
  );

  /// Address of the Whiskers backend, e.g. `https://api.example.com` or
  /// `http://localhost:8080` while developing. When set, the app talks to the
  /// server and never uses the provider keys above.
  static String get backendUrl => _get('BACKEND_URL');

  static bool get hasGeminiKey => geminiApiKey.isNotEmpty;
  static bool get hasApiKey => anthropicApiKey.isNotEmpty;
}
