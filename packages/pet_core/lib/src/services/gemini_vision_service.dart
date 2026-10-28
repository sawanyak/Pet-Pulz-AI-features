import 'package:http/http.dart' as http;

import '../provider_config.dart';
import 'screener_vision_service.dart';
import 'structured_vision.dart';

/// Photo health check using Gemini's vision.
class GeminiVisionService extends ScreenerVisionService {
  GeminiVisionService({
    http.Client? client,
    ProviderConfig config = const ProviderConfig(),
  }) : super(GeminiStructuredVision(client: client, config: config));
}
