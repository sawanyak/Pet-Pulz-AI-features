# Pet Pulz AI

A mobile app (Flutter) that helps cat owners with an AI assistant. The
assistant's persona in the prompts is called *Whiskers*; the app itself is
branded *Pet Pulz*.

| Feature | What it does | Where AI runs |
|---|---|---|
| **Chat** | Ask about behaviour, play, everyday care and symptoms. Replies stream in word by word, with Markdown formatting. Several chats are saved on the phone, with a history drawer (new, switch, delete). A Stop button cancels a reply. | Server or provider |
| **Voice mode** | Hands-free: it listens, answers aloud, then listens again. You can interrupt by tapping the orb. It stops listening after three silent rounds. | Speech is on the phone; the answer comes from the AI |
| **Photo health check** | Up to 3 photos of a visible concern. Returns an urgency level (*emergency*, *see a vet soon*, *monitor at home*, *can't tell*), what it sees, possible causes, safe home care and warning signs. A fixed disclaimer is always shown, and words like "trouble breathing" in your description force an emergency result. It is **not** a diagnosis. | Server or provider |
| **Photo studio** | Picks the mood, finds the cat's face, crops to 4:5 / 1:1 / original, brightens the photo, and suggests 3 captions plus hashtags. Shares through the phone's share sheet with the caption copied for you. | Captions: AI. Enhancing and cropping: on the phone |
| **Cat profile** | Name, age, breed, weight, sex, neutered, indoor/outdoor and notes. Used to personalise every answer. | Saved on the phone |

Not built yet: audio for video Reels, posting straight to Instagram (needs a
business account, Meta app review and a server), accounts.

## How it fits together

```
 Flutter app (lib/)  ──►  Backend server (backend/)  ──►  Gemini or Claude
   screens, voice,         keys + prompts live here,         (the AI provider)
   photo enhancing         login, limits, budget
        │                          │
        └────── packages/pet_core ─┘   shared pure-Dart code: data models,
                                       prompts, provider clients, and the
                                       app <-> server contract
```

The app can reach the AI in three ways, chosen by your `.env` (see below):
**backend** (the right way for a real app), **direct** (keys inside the app,
fine only on your own machine) or **demo** (fake answers, no network).

### Project layout

```
lib/               the Flutter app
  home/              landing screen with quick actions
  chat/              chat screen, controller, saved chats
  voice/             hands-free voice mode
  screener/          photo health check
  studio/            photo studio (enhance, captions, share)
  profile/           cat profile
  backend/           client for the backend server
  theme/ widgets/    Pet Pulz look and shared widgets
  app_services.dart  picks backend / direct / demo
  config.dart        reads .env
packages/pet_core/ shared Dart code (see its README)
backend/           the server (see its README)
scripts/           test_all.sh
test/              app tests
```

## Run it locally

### What you need

- **Flutter 3.44.x** (stable, Dart 3.12). Check with `flutter --version`.
- **Xcode** and an iOS simulator (this project has been run on iOS only).
- **CocoaPods**: the text-to-speech plugin needs it.
  `brew install cocoapods`. If a build complains about UTF-8, run
  `export LANG=en_US.UTF-8` first.
- *Optional:* a [Gemini API key](https://aistudio.google.com/apikey) or a
  Claude key. Without any key the app runs in demo mode.
- *Optional:* Android Studio. The Android side is written but **untested**.

### 1. Get the dependencies

```bash
flutter pub get
```

### 2. Create your `.env`

```bash
cp .env.example .env
```

The app **will not build without a `.env` file** (it is bundled into the app,
even if empty). Then choose a mode by what you fill in:

| Mode | What to put in `.env` | Notes |
|---|---|---|
| **Demo** | nothing | Fake answers, no network. The chat shows a "Demo mode" banner. Good for trying the screens. |
| **Direct** | `GEMINI_API_KEY=…` (or `ANTHROPIC_API_KEY=…`) | Real AI. The key is inside the app, so use it **only on your own machine**. Gemini is used if both are set. |
| **Backend** | `BACKEND_URL=http://localhost:8080` | The app talks to your server (step 3) and ignores any keys in `.env`. This is the mode to ship. |

All the `.env` settings:

| Setting | Meaning |
|---|---|
| `GEMINI_API_KEY`, `GEMINI_MODEL` | Gemini key and model (default `gemini-2.5-flash`). |
| `ANTHROPIC_API_KEY`, `ANTHROPIC_MODEL` | Claude key and model (default `claude-sonnet-5-5`). |
| `BACKEND_URL` | Server address. iOS simulator: `http://localhost:8080`. Android emulator: `http://10.0.2.2:8080`. Release builds require `https`. |

`.env` is read only when the app **starts**: after changing it, stop and run
the app again (hot reload is not enough). It is git-ignored; never commit
real keys.

### 3. Start the backend (Backend mode only)

Skip this step in demo or direct mode.

```bash
cd backend
cp .env.example .env        # fill in TOKEN_SECRET and a provider key
dart pub get
dart run bin/server.dart    # -> "Whiskers backend listening on port 8080"
```

Make a secret with `openssl rand -hex 32`. Leave this terminal running. Full
details are in [backend/README.md](backend/README.md).

### 4. Start the app (in a second terminal)

```bash
open -a Simulator           # opens the iOS simulator
flutter devices             # lists device ids
flutter run -d <device-id>  # e.g. the id of "iPhone 17 Pro"
```

The first build takes a few minutes. While it runs: `r` hot reload,
`R` hot restart, `q` quit.

### Trying each feature on the simulator

- **Chat / profile:** work as on a phone.
- **Voice mode:** the first time, iOS asks for microphone and speech
  recognition permission (tap Allow). The simulator uses your Mac's
  microphone, but speech recognition on a simulator can be unreliable; a real
  phone is the dependable test.
- **Photo health check / studio:** the simulator has **no camera**, so use
  **Gallery**. To add your own photos to the simulator:
  `xcrun simctl addmedia booted ~/Pictures/my-cat.jpg`
- **Share to Instagram:** opens the real iOS share sheet. Instagram only
  appears if it is installed (it is not on a simulator).

### Demo video

Youtube demo video link: https://youtube.com/shorts/INeJ5KyOp6A

### Run the tests

```bash
./scripts/test_all.sh
```

This analyzes and tests all three packages: the shared package (15 tests), the
backend (56) and the app (192). No network or API keys are needed; the tests
use fakes. The app's analyzer currently reports a few info-level notes
(deprecated Material names in the newer screens); they are shown but do not
fail the run.

### If something goes wrong

| What you see | Why / what to do |
|---|---|
| `No supported devices found` | No simulator is running. `open -a Simulator`, then `flutter devices`. |
| Build fails mentioning `.env` | The file is missing: `cp .env.example .env`. |
| Build fails about CocoaPods or UTF-8 | `brew install cocoapods`, then `export LANG=en_US.UTF-8`. |
| *"Couldn't reach the Whiskers service"* | Backend mode, but the server is not running (step 3), or `BACKEND_URL` is wrong. Or blank `BACKEND_URL` to use direct/demo mode. |
| *"Too many requests right now"* | The AI provider's rate limit. A Gemini key on the free tier allows only a few requests per minute: wait, or enable billing. |
| *"The AI service is overloaded"* | The provider is busy. Use **Retry**. |
| "Demo mode: no API key set" banner in the chat | No key and no `BACKEND_URL` is set. |
| Changed `.env` but nothing changed | Restart the app fully; `.env` is only read at startup. |

## What the AI costs

Measured on Gemini 2.5 Flash with the project's real prompts (Claude figures
are estimates, because no Claude key was available to measure). Prices checked
on 26 Oct 2026 from the official pricing pages and **can change**: Gemini 2.5
Flash $0.30 in / $2.50 out per million tokens (thinking counts as output),
Claude Sonnet 5.5 $2 in / $10 out.

| One request | Gemini (measured) | Claude (estimated) |
|---|---|---|
| Text chat, first message | $0.0020 | $0.0061 |
| Voice chat, one answer | $0.0008 | $0.0024 |
| Photo health check, 1 photo | $0.0029 | $0.0103 |
| Photo studio | $0.0031 | $0.0120 |

- **Chat gets pricier as a conversation grows**, because the recent history
  (last 30 messages) is re-sent every time: a 6-message chat costs about
  $0.013 in total on Gemini, a 15-message chat about $0.043.
- A typical active user (18 chat messages, 10 voice answers, 2 health checks,
  4 studio posts a month) costs roughly **$0.07/month on Gemini** or
  **$0.26/month on Claude**.
- Most of the cost of photo features is Gemini's internal "thinking". Turning
  it down would cut those requests by about 65%, but it has not been changed
  (the health check's quality matters for safety).
- Speech recognition, speaking, photo enhancing and the cat profile run on
  the phone and cost nothing in API fees.

More detail, and the worst-case day under the server's caps, is in
[backend/README.md](backend/README.md#what-the-ai-costs).

## Privacy and data

- Your **cat profile and chats** are stored only on the phone
  (`shared_preferences`, unencrypted). Up to 50 chats are kept; **deleting a chat** erases it (**New chat** keeps the old one in the history list).
- **Messages, photos and the cat profile are sent to the AI provider** to get
  an answer (through your server in backend mode). The app does not keep photos.
- **Gemini's free tier is for development only.** Its terms say Google may use
  what you send to improve its products and that human reviewers may read it;
  it says not to submit personal information, and in the EEA/UK/Switzerland
  only the paid service may be used for apps with users. Turn on billing
  (paid tier) before real users use the app, and review the current terms.

## Before you release

1. Run the backend somewhere with **https**, and set `BACKEND_URL` to it
   (release builds refuse plain `http`).
2. **Empty the provider keys in the app's `.env`**: it is bundled into the app,
   so anything in it can be extracted.
3. Use a billing-enabled provider key on the **server**, with spending limits.
4. Follow the checklist in [backend/README.md](backend/README.md).

## Status and known limits

- Tested on the **iOS simulator** only. Android, a real iPhone, and real cat
  photos have **not** been tried.
- Voice recognition has not been tested with a real voice.
- The backend's Dockerfile and Cloud Run steps have not been built or run.
- The assistant is not a vet. The health check can miss things.
- Next steps worth doing: app attestation (Apple App Attest / Play
  Integrity) so only genuine copies can sign up, audio for Reels, Android
  testing.
