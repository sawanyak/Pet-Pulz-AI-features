/// Keys and model names for the two AI providers.
///
/// The provider clients used to read these from the Flutter app's `.env`
/// file. That tied them to Flutter, so they could not run on a server. Now
/// whoever creates a client (the app in development, the server in
/// production) passes a [ProviderConfig] in.
class ProviderConfig {
  const ProviderConfig({
    this.geminiApiKey = '',
    this.geminiModel = defaultGeminiModel,
    this.anthropicApiKey = '',
    this.anthropicModel = defaultAnthropicModel,
  });

  static const defaultGeminiModel = 'gemini-2.5-flash';
  static const defaultAnthropicModel = 'claude-sonnet-5-5';

  final String geminiApiKey;
  final String geminiModel;
  final String anthropicApiKey;
  final String anthropicModel;

  bool get hasGemini => geminiApiKey.isNotEmpty;
  bool get hasAnthropic => anthropicApiKey.isNotEmpty;

  /// True if at least one provider can be used.
  bool get hasAny => hasGemini || hasAnthropic;
}
