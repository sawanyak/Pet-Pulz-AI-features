import 'package:http/http.dart' as http;

import '../provider_config.dart';
import 'screener_vision_service.dart';
import 'structured_vision.dart';

/// Photo health check using Claude's vision.
class ClaudeVisionService extends ScreenerVisionService {
  ClaudeVisionService({
    http.Client? client,
    ProviderConfig config = const ProviderConfig(),
  }) : super(ClaudeStructuredVision(client: client, config: config));
}
