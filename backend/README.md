# Whiskers backend

A small server that sits between the Whiskers app and the AI providers
(Gemini / Claude).

**Why it exists.** Anything inside a mobile app can be extracted, including an
API key. With this server the keys and the prompts live on the server; the app
only ever talks to the server.

```
  Whiskers app                    Whiskers backend                 AI provider
 ─────────────                   ──────────────────              ──────────────
  chat / photos  ── HTTPS ──►   check login token
  (plain data,                  check rate limits + daily budget
   never prompts)               build the prompt (server-owned)
                                add the API key            ──►    Gemini / Claude
  streamed reply ◄── SSE ────   stream the answer back      ◄──
```

Written in Dart with [`shelf`](https://pub.dev/packages/shelf). It shares its
data models, prompts, provider clients and the request/response contract with
the app through [`packages/pet_core`](../packages/pet_core/README.md). For the
whole project (the app, and how to run everything) see the
[root README](../README.md).

## Run it on your computer

You need the Dart SDK (it comes with Flutter) and a provider key.

```bash
cd backend
cp .env.example .env          # then fill in TOKEN_SECRET and a provider key
dart pub get
dart run bin/server.dart      # -> "Whiskers backend listening on port 8080"
```

Generate the secret with `openssl rand -hex 32`. Leave the server running in
its own terminal, then start the app in another (see the root README). The
server writes one log line per request to the terminal.

To stop it, press `Ctrl+C` (it finishes requests in progress first).

Point the app at it by adding one line to the **app's** `.env` (project root):

```
BACKEND_URL=http://localhost:8080        # iOS simulator
BACKEND_URL=http://10.0.2.2:8080         # Android emulator
```

When `BACKEND_URL` is set the app uses the server and **ignores** any provider
keys in its own `.env`.

Quick check that it works:

```bash
curl localhost:8080/health                       # {"status":"ok"}
TOKEN=$(curl -s -X POST localhost:8080/v1/register | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
curl -N -X POST localhost:8080/v1/chat -H "authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' \
  -d '{"messages":[{"role":"user","text":"Why do cats purr?"}]}'
```

## Configuration

Environment variables (a `.env` file in the current folder is read too; real
environment variables win). The server refuses to start if the secret or the
provider key is missing.

| Variable | Default | Meaning |
|---|---|---|
| `TOKEN_SECRET` | *(required, 32+ chars)* | Signs login tokens. Anyone who knows it can forge tokens. |
| `GEMINI_API_KEY` / `ANTHROPIC_API_KEY` | | At least one is required. |
| `GEMINI_MODEL` / `ANTHROPIC_MODEL` | `gemini-2.5-flash` / `claude-sonnet-5-5` | |
| `PROVIDER` | `auto` | `auto` (Gemini if its key is set), `gemini` or `anthropic`. |
| `PORT` | `8080` | |
| `CHAT_PER_MINUTE` / `CHAT_PER_DAY` | `20` / `400` | Per install. |
| `VISION_PER_MINUTE` / `VISION_PER_DAY` | `8` / `60` | Per install; health check and studio share it. |
| `REGISTER_PER_HOUR` | `10` | Sign-ups per IP address. |
| `TOKEN_TTL_DAYS` | `30` | How long a login token lasts. |
| `DAILY_REQUEST_CAP` | `5000` | **Total** AI calls per UTC day across everyone. The wallet guard. |
| `MAX_CONCURRENT` | `40` | AI calls running at once. |
| `TRUSTED_PROXY_HOPS` | `0` | Number of load balancers in front (Cloud Run = 1). See below. |

## What the AI costs

Every cost here is for the AI provider; hosting the server is separate.
Figures for **Gemini 2.5 Flash are measured** by running each feature through
this project's own code and reading the token counts Gemini reports (15
calls, a generated test photo rather than a real cat photo). **Claude
figures are estimates**: there was no Claude key to measure with, so they
assume Claude's tokenizer counts about 15% more tokens than Gemini's, about
350 extra tokens for the forced tool call, and image tokens of width × height
÷ 750. Treat every number as roughly ±30%; output length varies a lot from
call to call.

Prices (checked 26 Oct 2026 on the official pricing pages; they can change),
per million tokens:

| Model | Input | Output |
|---|---|---|
| Gemini 2.5 Flash | $0.30 | $2.50 (the model's internal "thinking" counts as output) |
| Claude Sonnet 5.5 | $2.00 | $10.00 |

### One request

| Feature | Input tokens | Output tokens (reply + thinking) | Gemini (measured) | Claude (estimated) |
|---|---|---|---|---|
| Text chat, first message | 542 | 724 (420 + 304) | **$0.0020** | **$0.0061** |
| Voice chat, one answer | 660 | 237 (74 + 163) | **$0.0008** | **$0.0024** |
| Photo health check, 1 photo | 1,386 | 988 (251 + 737) | **$0.0029** | **$0.0103** |
| Photo health check, 3 photos | 1,904 | 1,024 (249 + 775) | **$0.0031** | **$0.0169** |
| Photo studio | 1,083 | 1,118 (300 + 818) | **$0.0031** | **$0.0120** |

Per 1,000 requests: chat $1.97, voice $0.79, health check $2.89, studio $3.12
on Gemini (about 3 to 4 times that on Claude).

### What moves the cost

- **Conversation length.** The AI has no memory, so each chat request re-sends
  the recent history (at most the last 30 messages). The input grows by about
  450 tokens per message. A 6-message chat costs about $0.013 in total on
  Gemini and a 15-message chat about $0.043; after that it levels off.
- **Gemini's "thinking".** It is about 75% of the output tokens for the
  health check and studio, and about 70% for voice. Switching it off would
  lower the cost per request by roughly 65% (studio, health check), 52%
  (voice) and 23% (chat). This is **not** done: the health check's quality
  affects safety, so reduce it only deliberately.
- **Photos are cheap on Gemini** (about 258 tokens each) but cost much more
  on Claude (about 1,600 tokens for a 1280 × 960 photo, estimated).

### A typical user, and the worst day

Assuming one user a month sends 18 chat messages (3 chats of 6), 10 voice
answers, 2 health checks and 4 studio posts:

| | Gemini | Claude (est.) |
|---|---|---|
| Per active user per month | **$0.066** | **$0.262** |
| 1,000 such users | **$66** | **$262** |

With the default `DAILY_REQUEST_CAP=5000`, the **most a day can cost**, if
every call were the most expensive kind, is about **$24 (chat) to $29
(photos) on Gemini** and about **$139 on Claude**. Lower the cap to what you
are willing to pay.

### The Gemini free tier

A Gemini key without billing runs on the free tier: no charge, but only a few
requests per minute (you will see "Too many requests" quickly), and the limits
"are subject to change". More importantly, its terms are for development:
Google may use what you send to improve its products, human reviewers may read
it, you are told not to submit personal information, and in the
EEA/UK/Switzerland only the paid service may be used when making an app
available to users. Cat photos, chats and profiles are personal data, so
**enable billing before any real user uses the app**. Nothing is charged until
you set up billing yourself. Because the key lives only on this server, the
switch is one line in `backend/.env`.

## API

All request and response formats are defined once, in
`packages/pet_core/lib/src/api/protocol.dart`, and used by both the app and
the server. Errors are always `{"error": {"code": "...", "message": "..."}}`.

| Endpoint | Auth | Purpose |
|---|---|---|
| `GET /health` | no | Liveness check. |
| `POST /v1/register` | no (IP-limited) | Returns `{token, expiresAt}`. Send a still-valid token to renew it and keep the same identity. |
| `POST /v1/chat` | Bearer token | Body `{messages, cat?, spoken?}`. Streams Server-Sent Events: `delta`, then `done` (or `error`). |
| `POST /v1/screen` | Bearer token | Photo health check. Body `{photos[1-3], concern?, duration?, cat?}`. Returns the result JSON. |
| `POST /v1/studio` | Bearer token | Captions, hashtags, mood and crop focus for one photo. Body `{photo, note?, cat?}`. |

Status codes: `400` invalid request, `401` bad/expired token, `413` too large,
`429` rate limit or daily quota (with `Retry-After`), `502` the AI provider
failed, `503` service busy or the daily budget is spent.

## Security: what it does, and what it does not

**What it protects**

- **Provider keys never leave the server.** The app has no key at all.
- **The app cannot send a prompt.** The server builds every instruction from
  plain data (messages, cat profile). If it accepted prompts, anyone who found
  the server's address could use it as a free general-purpose AI. A test
  checks that the app's requests contain no prompt text.
- **Signed anonymous tokens.** Each installation registers and gets a token
  signed with `TOKEN_SECRET` (HMAC-SHA256, compared in constant time).
  Forged, altered, expired or wrong-secret tokens are rejected before any
  paid call happens.
- **Cost limits at three levels:** per-install per-minute and per-day, a
  per-IP limit on sign-ups, and a **global daily cap** that bounds your worst
  day no matter what.
- **Input limits.** Message count and length, photo count, size and type, and
  the whole request body are capped. Oversized bodies are cut off while
  reading, so a huge upload can't fill memory.
- **Private logs.** One JSON line per request: id, method, path, status, time,
  and a short hash of the anonymous install. **Never** message text, captions,
  photos, cat details, tokens or keys (a test scans the logs for these).
- **Errors don't leak.** Crashes become a generic 500. Provider configuration
  problems (wrong key or model) are logged for you but shown to users only as
  "temporarily unavailable".
- **A dropped connection stops the AI call** instead of paying for an answer
  nobody will read.

**What it does NOT protect against (be aware)**

- **There are no user accounts.** Identities are anonymous and free. Someone
  determined can register many identities (10 per hour per IP address) and use
  the free quota of each. The **global daily cap** is what keeps this from
  becoming an unbounded bill; a determined attacker can use up the day's
  budget and make honest users see "very busy today". This is the main reason
  to add app attestation (below) before a large launch.
- **Limits are held in memory.** They reset when the server restarts, and each
  instance counts separately. Fine for one small instance; use Redis or
  similar before running several.
- **The server sees the content** of messages and photos while forwarding
  them to the provider (it has to). It does not store them, but you are
  responsible for the server's hosting and for your privacy policy.
- **`TRUSTED_PROXY_HOPS` must be right.** Behind a proxy the server reads the
  client IP from `X-Forwarded-For`, counting from the right. Too high or too
  low lets clients fake their IP and dodge the sign-up limit.
- **Tokens are stored unencrypted on the phone.** They identify nobody and
  only unlock that install's own quota.
- Also set **spending limits at the provider** (Google AI Studio / Anthropic
  console) as a second, independent safety net.

## Deploying (example: Google Cloud Run)

These commands were not run while building this project; treat them as a
starting point and check the current Cloud Run documentation.

```bash
# 1. Build the image from the PROJECT ROOT (it needs packages/pet_core too).
docker build -f backend/Dockerfile \
  -t REGION-docker.pkg.dev/PROJECT/REPO/whiskers-backend .

# 2. Push it to your registry (Artifact Registry in this example).
docker push REGION-docker.pkg.dev/PROJECT/REPO/whiskers-backend

# 3. Deploy the image.
gcloud run deploy whiskers-backend \
  --image REGION-docker.pkg.dev/PROJECT/REPO/whiskers-backend \
  --region REGION --allow-unauthenticated --max-instances 1 \
  --set-env-vars TRUSTED_PROXY_HOPS=1,DAILY_REQUEST_CAP=2000 \
  --set-secrets TOKEN_SECRET=whiskers-token-secret:latest,GEMINI_API_KEY=gemini-key:latest
```

- `--allow-unauthenticated` is right: the app authenticates with its own
  tokens, not Google identities.
- Keep **`--max-instances 1`** while limits live in memory.
- Put secrets in Secret Manager, not in the command line or the image.
  `.dockerignore` already keeps `.env` files out of the image.
- Cloud Run gives you `https://…run.app`. Put that in the app's `BACKEND_URL`.

### Before you release the app

1. `BACKEND_URL` is your **https** address (release builds refuse plain http).
2. The app's `.env` contains **no** provider keys (it is bundled into the app).
3. `TOKEN_SECRET` is long and random, stored as a secret.
4. The provider key is from a **billing-enabled** project (the free tier is
   not allowed for real users' data, see above), with provider-side spending
   limits and budget alerts set.
5. `DAILY_REQUEST_CAP` matches what you are willing to pay in a day.
6. `TRUSTED_PROXY_HOPS` matches your hosting.
7. Set up an alert for `503`/`429` spikes and for cost.

## Tests

```bash
./scripts/test_all.sh      # from the project root: shared package, backend, app
cd backend && dart test    # just this package
```

The backend has 56 tests (the whole project has 263). They call the real
request handler with fake AI services (no network, no keys): tokens, every
limit, streaming, validation, disconnects, log privacy and error handling.

## Troubleshooting

| What you see | Why / what to do |
|---|---|
| `Configuration error: TOKEN_SECRET is required…` | The server refuses to start without a secret of 32+ characters. `openssl rand -hex 32`. |
| `Configuration error: Set GEMINI_API_KEY or ANTHROPIC_API_KEY…` | No provider key in `backend/.env`. |
| `Address already in use` | Something is on port 8080 (often an old copy of the server). Stop it, or set `PORT`. |
| App says *"Couldn't reach the Whiskers service"* | The server is not running, or the app's `BACKEND_URL` is wrong. Check `curl localhost:8080/health`. |
| `401` in the log, then a new `/v1/register` | Normal after you change `TOKEN_SECRET` or restart with a new one: the app signs up again by itself. |
| `429` `rate_limited` / `quota_exceeded` | Your own limits (see Configuration). Wait, or raise them for testing. |
| `503` `busy` | The `DAILY_REQUEST_CAP` is used up for today (UTC), or `MAX_CONCURRENT` is reached. |
| *"The assistant is temporarily unavailable"* | The provider rejected the server's key or model. The real reason is in the server log (`note`). |
| *"Too many requests right now"* from the provider | A free-tier rate limit. Wait a minute, or enable billing. |

## Next hardening steps

1. **App attestation** — Apple App Attest / Google Play Integrity — so only
   genuine copies of your app can register. This is the real answer to
   "anonymous identities are free".
2. Shared rate-limit state (Redis) to run more than one instance.
3. Optional accounts (sign in with Apple/Google) for per-user quotas or a paid
   tier.
4. Alerting/metrics, and a `/metrics` endpoint.
5. `flutter_secure_storage` for the app's token.
