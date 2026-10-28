# pet_core

The shared, **pure-Dart** core of the Pet Pulz AI project. The Flutter app
(`lib/`) and the backend server (`backend/`) both depend on it, so the two can
never disagree about a prompt, a data format or a size limit.

It has **no Flutter dependency** (only `package:http`), which is what lets it
run on a server as well as in the app.

## What is inside

```
lib/pet_core.dart            one import for everything:
                             import 'package:pet_core/pet_core.dart';
lib/src/
  models/                    CatProfile, ChatMessage, HealthScreening (+ the
                             emergency-words safety net), ContentSuggestion
                             (mood, captions, hashtags, Instagram limits)
  services/
    ai_service.dart          AiService: chat as a stream of text pieces
    pet_assistant_prompt.dart  the chat instructions, built from the cat
                             profile (and a "spoken" style for voice mode)
    screener_prompt.dart     health-check instructions + JSON schema
    content_prompt.dart      photo-studio instructions + JSON schema
    claude_*.dart, gemini_*.dart  the provider clients (chat, photos)
    structured_vision.dart   "photos in, JSON out" for both providers
    screener_vision_service.dart, content_service.dart  the two photo features
    mock_*.dart              fake services for demo mode and tests
    sse.dart                 Server-Sent Events parsing
  api/protocol.dart          THE APP <-> SERVER CONTRACT: request and
                             response shapes, size limits, routes, error codes
  provider_config.dart       keys and model names, passed in by the caller
```

## Rules of thumb

- **Prompts live here, and only here.** The app never sends a prompt to the
  server; it sends plain data (see `ChatRequest`, `ScreenRequest`,
  `StudioRequest`) and the server builds the instructions from this package.
- **Keys are never read here.** Whoever creates a client passes a
  `ProviderConfig`: the app in development, the server in production.
- **Cancellation matters.** A Dart `async*` generator that is waiting for the
  next chunk cannot be cancelled until that chunk arrives. So `sse.dart` is
  built from stream transformers, and the app's backend client and the server
  use held subscriptions, so Stop and dropped connections take effect
  immediately there. The direct Claude/Gemini chat clients here
  (`claude_ai_service.dart`, `gemini_ai_service.dart`) are still `async*`
  generators, so when they are cancelled the provider call really ends when its
  next chunk arrives (normally within a moment). Keep this in mind if you
  change the streaming code.
- **Changing the contract?** Edit `api/protocol.dart`: the app and the
  server will both stop compiling until they agree again, and its tests show
  what the limits are.

## Tests

```bash
cd packages/pet_core
dart pub get
dart analyze
dart test        # 15 tests: request validation, size limits, JSON round trips
```

More of this package's behaviour (prompts, provider clients, the safety net)
is covered by the app's tests in `test/` and the backend's in `backend/test/`.
Run everything from the project root with `./scripts/test_all.sh`.
