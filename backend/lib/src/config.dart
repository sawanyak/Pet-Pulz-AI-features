import 'package:pet_core/pet_core.dart';

/// Which AI provider serves requests.
enum ProviderChoice { gemini, anthropic }

/// Thrown at startup when the configuration is unusable, so the server fails
/// loudly at boot instead of half-working later.
class ConfigException implements Exception {
  ConfigException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Everything configurable, read from environment variables.
///
/// Limits are per install (one app installation = one anonymous identity).
class ServerConfig {
  const ServerConfig({
    required this.tokenSecret,
    required this.providers,
    required this.provider,
    this.port = 8080,
    this.tokenTtl = const Duration(days: 30),
    this.chatPerMinute = 20,
    this.chatPerDay = 400,
    this.visionPerMinute = 8,
    this.visionPerDay = 60,
    this.registerPerHourPerIp = 10,
    this.dailyRequestCap = 5000,
    this.maxConcurrentProviderCalls = 40,
    this.trustedProxyHops = 0,
  });

  /// Secret used to sign tokens. Anyone who knows it can mint valid tokens.
  final String tokenSecret;

  /// Provider keys and model names.
  final ProviderConfig providers;

  /// Which of the configured providers is used.
  final ProviderChoice provider;

  final int port;
  final Duration tokenTtl;

  final int chatPerMinute;
  final int chatPerDay;
  final int visionPerMinute;
  final int visionPerDay;
  final int registerPerHourPerIp;

  /// Total provider calls per UTC day across ALL users: the wallet guard.
  final int dailyRequestCap;

  /// Provider calls running at the same moment.
  final int maxConcurrentProviderCalls;

  /// How many reverse proxies (load balancers) sit in front of the server.
  /// 0 = clients connect directly, so the socket address is the client IP.
  /// 1 = one proxy (for example Cloud Run) that appends the client IP to
  /// X-Forwarded-For. Getting this wrong lets clients fake their IP.
  final int trustedProxyHops;

  static const minSecretLength = 32;

  factory ServerConfig.fromEnv(Map<String, String> env) {
    String get(String k) => (env[k] ?? '').trim();
    int number(String k, int fallback, {int min = 0, int max = 1 << 30}) {
      final raw = get(k);
      if (raw.isEmpty) return fallback;
      final v = int.tryParse(raw);
      if (v == null || v < min || v > max) {
        throw ConfigException('$k must be a whole number from $min to $max.');
      }
      return v;
    }

    final secret = get('TOKEN_SECRET');
    if (secret.length < minSecretLength) {
      throw ConfigException(
        'TOKEN_SECRET is required and must be at least $minSecretLength '
        'characters. Generate one with: openssl rand -hex 32',
      );
    }

    final providers = ProviderConfig(
      geminiApiKey: get('GEMINI_API_KEY'),
      geminiModel: get('GEMINI_MODEL').isEmpty
          ? ProviderConfig.defaultGeminiModel
          : get('GEMINI_MODEL'),
      anthropicApiKey: get('ANTHROPIC_API_KEY'),
      anthropicModel: get('ANTHROPIC_MODEL').isEmpty
          ? ProviderConfig.defaultAnthropicModel
          : get('ANTHROPIC_MODEL'),
    );
    if (!providers.hasAny) {
      throw ConfigException(
        'Set GEMINI_API_KEY or ANTHROPIC_API_KEY: the server needs at least '
        'one AI provider.',
      );
    }

    final ProviderChoice choice;
    switch (get('PROVIDER').toLowerCase()) {
      case '':
      case 'auto':
        choice = providers.hasGemini
            ? ProviderChoice.gemini
            : ProviderChoice.anthropic;
      case 'gemini':
        if (!providers.hasGemini) {
          throw ConfigException('PROVIDER=gemini but GEMINI_API_KEY is empty.');
        }
        choice = ProviderChoice.gemini;
      case 'anthropic':
        if (!providers.hasAnthropic) {
          throw ConfigException(
            'PROVIDER=anthropic but ANTHROPIC_API_KEY is empty.',
          );
        }
        choice = ProviderChoice.anthropic;
      default:
        throw ConfigException('PROVIDER must be auto, gemini or anthropic.');
    }

    return ServerConfig(
      tokenSecret: secret,
      providers: providers,
      provider: choice,
      port: number('PORT', 8080, min: 1, max: 65535),
      tokenTtl: Duration(days: number('TOKEN_TTL_DAYS', 30, min: 1, max: 365)),
      chatPerMinute: number('CHAT_PER_MINUTE', 20, min: 1),
      chatPerDay: number('CHAT_PER_DAY', 400, min: 1),
      visionPerMinute: number('VISION_PER_MINUTE', 8, min: 1),
      visionPerDay: number('VISION_PER_DAY', 60, min: 1),
      registerPerHourPerIp: number('REGISTER_PER_HOUR', 10, min: 1),
      dailyRequestCap: number('DAILY_REQUEST_CAP', 5000, min: 1),
      maxConcurrentProviderCalls: number('MAX_CONCURRENT', 40, min: 1),
      trustedProxyHops: number('TRUSTED_PROXY_HOPS', 0, min: 0, max: 5),
    );
  }
}

/// Reads a `.env` file's text: `KEY=value` lines, `#` comments, optional
/// quotes. Real environment variables should override it (see server.dart).
Map<String, String> parseEnvFile(String text) {
  final out = <String, String>{};
  for (final rawLine in text.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final eq = line.indexOf('=');
    if (eq <= 0) continue;
    final key = line.substring(0, eq).trim();
    var value = line.substring(eq + 1).trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    out[key] = value;
  }
  return out;
}
