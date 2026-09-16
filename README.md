# MCGEE UI

Flutter host app for the MCGEE narration engine. The current runnable target is
the web app; Android and Windows runners remain in the project. The narration
engine is a separate package at `packages/narration_engine` and must stay usable
without importing this app.

## Run the web slice

```sh
flutter pub get
flutter run -d chrome
```

Allow camera access when prompted. The web app does not request, receive, or
embed provider credentials. OpenRouter and Fish Audio keys exist only in the
Netlify Function environment. Native IO builds still read local secret files.

Web narration uses the scale-to-zero Netlify Function at `/api/narrate`. The
function opens OpenRouter's text stream and Fish Audio's live WebSocket in
parallel, feeds text deltas into Fish as they arrive, then returns one MP3 plus
the spoken text. No local relay or always-on VM is required. If Fish fails, the
function automatically synthesizes the completed line through OpenRouter.

Local web development defaults to
`https://mcgee-narrator.netlify.app/api/narrate`. Override it when running a
different deployment with:

```sh
flutter run -d chrome \
  --dart-define=NARRATION_API_URL=https://example.netlify.app/api/narrate
```

Native IO builds can still connect directly to Fish using
`.secrets/fishaudio-key`; those builds do not use the Netlify endpoint.

After narrator setup connects, an image-free OpenRouter request immediately
generates a fictional film title, invented director credit, and 35–55-word
opening voiceover that names the saved protagonist. The name and spoken story
memory use `shared_preferences` (browser `localStorage` on web). A returning
episode skips a new generic opening so its previous final beat remains the one
continued by the first live capture. The shared opening prompt is
`lib/assets/film-opening-prompt.json`; native and Netlify paths both use it.
Speech preparation starts as soon as those credits arrive, during camera
consent. The camera button presents the credits on black while acquiring the
camera. After at least three seconds of visible credits, the prepared opening
plays and the camera fades in on the actual playback-start event. Live frames
then prepare action narration during the opening, through the same serialized
audio queue. Provider latency can still leave a gap after the opening. If the
opening request or its speech fails, the app proceeds to live narration.

The browser samples one JPEG every two seconds, resizes it to a 512-pixel
longest edge, and encodes it at JPEG quality 65 before submission. The live path
sends that frame straight to the narration model, avoiding both the old
three-frame/ten-second warm-up and a separate sequential vision request. While
preparation is busy, newer frames collapse into one latest-frame slot. Spoken
MP3 bytes are played through the host's `AudioOutput` adapter, and the line is
also shown as a subtitle. A randomized 0.5–2 second pause separates completed
narration segments so prefetched passages do not play back-to-back.

Browser captures remain in memory because a web page cannot write the host file
contract directly. IO hosts use application support storage and save:

```text
captures/webcam/{unix-seconds}.jpg
```

Use localhost or HTTPS: browser camera access requires a secure context.
Runtime failures are printed to the browser/debug console with an `[MCGEE]`
prefix, including provider HTTP errors and stack traces when available.

## Integration map

- `packages/narration_engine/`: provider-neutral engine, OpenRouter adapters,
  offline generator, and package tests.
- `lib/openrouter_runtime.dart`: the app's composition root. It owns one
  long-lived engine and the low-latency single-frame narration path.
- `lib/netlify_narration_renderer.dart`: fused web request/response adapter.
- `netlify/functions/narrate.mjs`: on-demand OpenRouter-to-Fish orchestration.
- `lib/audio_output.dart`: `audioplayers` implementation of `AudioOutput`.
- `lib/capture_store*.dart`: bytes in the browser; timestamped files on IO
  platforms.
- `lib/main.dart`: camera lifecycle, two-second sampling, startup choices, and
  host UI only.

The host should keep one engine for a session so narrative memory, fictional
canon, repetition checks, pacing, and silence decisions survive between capture
windows. Older spoken lines roll into a bounded recap while the ten most recent
lines remain verbatim. Only narration that actually starts playback is saved.
It should call `stop()` when the app lifecycle suspends capture and
`close()` at teardown.
Do not move camera ownership or audio playback into the package.

Narration describes the visible action or posture and a concrete scene detail
before adding a brief theatrical interpretation. Each prompt carries recent
spoken lines in order and singles out the last line to continue the same
activity or story thread. On the Netlify path, the live writer also returns a
structured story recap, current activity, unresolved thread, and recurring
elements; these become authoritative context for the next frame rather than
relying on transcript wording alone. Native direct-provider builds retain the
bounded spoken history and rolling recap. The current image takes precedence
over earlier
speculation; unchanged scenes continue the activity, and scene changes prompt
a transition. These rules apply to all five languages and both the Netlify and
native writers.

The package adapters default to `openai/gpt-5.6-terra`, used as a multimodal
writer in one pass with high reasoning effort. OpenRouter is asked to
rank providers by latency. Live passages are one 10–20-word sentence and are
discarded when their source frame is more than 20 seconds old, leaving enough
time for multimodal writing and speech synthesis. Narration text streams into
Fish Audio S2.1 concurrently instead of waiting for the full sentence first.
The host exposes exactly three narrator choices:

```dart
OpenRouterVoiceOption.morganFreeman     // Fish Audio
OpenRouterVoiceOption.davidAttenborough // Fish Audio
OpenRouterVoiceOption.jade              // Grok Voice TTS `eve`
```

Each typed option keeps its provider model and voice ID paired. Never place a
raw voice ID, API key, or face-identification behavior in the core.

At startup the host also exposes English, French, Spanish, Italian, and Catalan
narration. All editorial instructions and context labels use shared English
prompts, with an English directive to compose directly in the selected output
language using natural idiom rather than translating an English draft. The film
title and opening voiceover are generated in the selected language; the
director credit uses the fixed prefix “A FILM BY”. The selected `en`, `fr`,
`es`, `it`, or `ca` value is sent to the Netlify function.

## Validation

```sh
flutter analyze
flutter test
flutter build web --release

cd packages/narration_engine
dart analyze
dart test
dart run bin/generate_webcam_track.dart
```

## Deploy the web app

The Netlify site is `mcgee-narrator`. Provider keys are server-side environment
variables and must never be added to Flutter assets or committed:

```sh
netlify env:set OPENROUTER_API_KEY "$(<.secrets/openrouter-key)" \
  --context production --secret
netlify env:set FISH_AUDIO_API_KEY "$(<.secrets/fishaudio-key)" \
  --context production --secret
npm install
npm test
flutter build web --release
netlify deploy --prod --dir=build/web --functions=netlify/functions
```

The offline generator reads `packages/narration_engine/.secrets/openrouter-key`
by default. That nested secret file is intentionally absent from Git; pass
`--api-key-file PATH` when the key lives elsewhere.

The private-circle web endpoint relies on its origin policy, per-IP rate limit,
and unadvertised deployment rather than an end-user login. Add real user
authentication before making the URL public. Do not embed shared provider
credentials in web assets or `--dart-define` values.
