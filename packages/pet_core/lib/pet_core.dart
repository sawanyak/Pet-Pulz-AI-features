/// Shared core of the Whiskers app (see pubspec description).
library;

// The app <-> backend contract
export 'src/api/protocol.dart';

// Models
export 'src/models/cat_profile.dart';
export 'src/models/chat_message.dart';
export 'src/models/content_suggestion.dart';
export 'src/models/health_screening.dart';

// Configuration
export 'src/provider_config.dart';

// AI: interfaces, prompts and provider clients
export 'src/services/ai_service.dart';
export 'src/services/claude_ai_service.dart';
export 'src/services/claude_vision_service.dart';
export 'src/services/content_prompt.dart';
export 'src/services/content_service.dart';
export 'src/services/gemini_ai_service.dart';
export 'src/services/gemini_vision_service.dart';
export 'src/services/mock_ai_service.dart';
export 'src/services/mock_vision_service.dart';
export 'src/services/pet_assistant_prompt.dart';
export 'src/services/screener_prompt.dart';
export 'src/services/screener_vision_service.dart';
export 'src/services/sse.dart';
export 'src/services/structured_vision.dart';
export 'src/services/vision_service.dart';
