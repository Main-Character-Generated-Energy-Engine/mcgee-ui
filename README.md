# MCGEE UI

Flutter camera narration app. OpenRouter writes short passages from camera
frames; Fish Audio `s2.1-pro-free` speaks them. There is no OpenRouter speech
fallback.

## Run

Install Flutter (with Chrome support) and Node.js, then run `flutter pub get`.
Set `OPENROUTER_API_KEY` and `FISH_AUDIO_API_KEY`, or put each key in its
ignored local file:

```text
.secrets/openrouter-key
.secrets/fishaudio-key
```

| Command | Purpose |
| --- | --- |
| `npm run dev:web` | Launch Chrome and a local Fish speech relay on port 8767. |
| `npm run dev:e2e` | Launch the browser test app at `http://localhost:8770`; no keys or camera permission needed. |
| `node scripts/web.mjs check` | Check local credentials without printing them. |
| `npm run build:web` | Build release assets in `build/web`. |
| `npm test` | Test the browser player and speech relay. |
| `flutter test` | Run Flutter tests. |
| `flutter analyze` | Check Dart code. |

The web build calls OpenRouter directly; **its key is visible to visitors**.
Fish requests go through `netlify/functions/speech.mjs` in production and
`scripts/speech-dev.mjs` locally. Fish's HTTP TTS endpoint does not accept our
browser CORS preflight, and its TTS WebSocket requires an authorization header
that browser WebSockets cannot set. The Fish key stays on the server. The
speech relay currently has no user sign-in; secure and meter it before opening
the site to others. Native builds read the local keys at runtime and use Fish
WebSocket directly.

## Browser end-to-end test

Run `npm run dev:e2e`. Enter a name and press Enter, then press Enter on the
camera consent screen. The app cycles through
`test/fixtures/mock-camera-feed/1.jpg` to `4.jpg` every two seconds. Local mock
OpenRouter and Fish responses exercise
the opening, live narration, speech request, and browser playback paths. Check
`http://127.0.0.1:8767/__e2e/state` for request counts and `distinctFrames`;
the latter should increase as live narration uses different camera images.
This mode is enabled only by launcher supplied Dart defines.

## Audio and latency

The web relay forwards Fish's response body as it arrives. The browser appends
MP3 bytes to MediaSource and can play before the response ends; browsers without
MP3 MediaSource support buffer the passage first. The app uses Fish's `low`
latency setting. It does **not** fetch a complete MP3 before playback on the
normal browser path.

The web writer must finish a passage before Fish starts. Camera
sampling (every two seconds), writing, Fish first audio, and a deliberate
0.5–2 second gap between passages all affect perceived delay. WebSocket TTS
alone would not remove the writing wait. Debug builds log the
speech request's first-audio time. Fish's free tier is subject to its
[current terms](https://fish.audio/blog/s2-1-pro-free-api/), including no
latency guarantee.

Opening preparation and browser speech startup have a 10-second deadline.
If opening playback has not started 10 seconds after camera activation, the
app shows an audio error and logs the failed stage for debugging.

## Code map

| Path | Role |
| --- | --- |
| `lib/main.dart` | App UI, camera lifecycle, and mock camera switch. |
| `lib/openrouter_runtime.dart` | Wires the narration engine and providers. |
| `lib/src/` | Narration engine, OpenRouter, and native Fish adapters. |
| `lib/direct_narration_renderer.dart` | Sends each complete web passage to speech. |
| `lib/direct_http_speech_synthesizer.dart` | Receives streamed HTTP speech in the browser. |
| `netlify/functions/speech.mjs` | Authenticates to Fish and relays the audio stream. |
| `web/narration_audio.js` | Plays MP3 chunks through MediaSource. |
| `scripts/e2e-server.mjs` | Mock provider and inspection endpoint. |

The three voices use separate instructions in
`lib/assets/narrator-profiles.json`; shared live writing rules are in
`lib/src/core/writer_instructions.dart`, while `prompt_builder.dart` supplies
only scene and story context. The opening prompt is
`lib/assets/film-opening-prompt.json`. Name, language, and spoken story memory
are stored locally. Opening generation starts during setup, while camera
permission is pending. The camera view and capture loop start one second after
opening audio begins.

## Deploy

The Netlify site is `mcgee-narrator`. Set `FISH_AUDIO_API_KEY` as a Netlify
server environment variable. After installing and logging in to the Netlify
CLI, run `netlify link` for a new checkout, then `npm run deploy`. That command
runs tests, builds the web app, and deploys the static assets with the speech
function. A web build embeds the OpenRouter key supplied at build time.
