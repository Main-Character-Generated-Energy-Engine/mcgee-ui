# MCGEE UI

Flutter host app for the MCGEE narration engine. The current runnable target is
the web app; Android and Windows runners remain in the project. The narration
engine is a separate package at `packages/narration_engine` and must stay usable
without importing this app.

## Run the web slice

Run the local function server in one terminal (with the Netlify CLI installed):

```sh
npm install
npm run dev:functions
```

In another terminal, run Flutter:

```sh
flutter pub get
flutter run -d chrome
```

Allow camera access when prompted. The web app does not request, receive, or
embed provider credentials. OpenRouter and Fish Audio keys exist only in the
Netlify Function environment. Native IO builds still read local secret files.

Web narration uses the scale-to-zero Netlify Function at `/api/narrate`. The
function reads OpenRouter's structured narration and story state, validates the
name cadence, then sends the accepted spoken text to Fish Audio. It returns
spoken text/story metadata in headers and streams MP3 chunks as they arrive.
The browser appends those chunks to one MediaSource and starts playback before
the complete MP3 arrives. Browsers without MP3 MediaSource support fall back to
buffered playback and print a console notice. No always-on VM is required.
If Fish fails before its first audio chunk, the function falls back to
OpenRouter; a failure after audio starts terminates that passage instead of
splicing another provider into it. OpenRouter audio is forwarded as received,
but its upstream provider may still buffer.

Local web pages default to `http://localhost:8888/api/narrate` (preserving
`127.0.0.1` or IPv6 loopback when used). Debug builds also default to the local
function server, even when their page is hosted remotely. If the local server
isn't running, narration fails instead of falling back to production. Release
deployments use `/api/narrate` on their own origin, including deploy previews.
The debug console prints the resolved backend URL at connection time.

The dev launcher reads `OPENROUTER_API_KEY` and `FISH_AUDIO_API_KEY` from its
shell environment, falling back to `.secrets/openrouter-key` and
`.secrets/fishaudio-key`. It trims file-ending newlines, rejects missing or
obviously malformed credentials, and prints only their source, never their value.
Fish is optional; without it, speech uses OpenRouter. To check local credential
loading without launching anything, run `npm run dev:functions -- --check`.

Netlify Dev runs with `--offline`, so it watches local functions without fetching
remote environment variables or substituting AI Gateway credentials. The
functions themselves still call OpenRouter and Fish over the network. Production
keys stay in Netlify's hosted environment. Do not put keys in Flutter defines.
After editing shared prompt JSON, restart the local function server if its watcher
doesn't rebuild the function; hot-restart Flutter when changing bundled assets or
compile-time defines. If a local request returns an upstream HTTP 401, restart the
function server with the dev command above and check the printed credential source;
an explicit shell key takes priority over its local file.

To deliberately test a deployed backend, use an explicit override:

```sh
flutter run -d chrome \
  --dart-define=NARRATION_API_URL=https://example.netlify.app/api/narrate
```

Native IO builds can still connect directly to Fish using
`.secrets/fishaudio-key`; those builds do not use the Netlify endpoint.

After narrator setup connects, an image-free OpenRouter request immediately
generates a fictional film title, invented director credit, and 25–45-word
opening voiceover in the selected narrator mode. Each opening names the saved
protagonist and establishes a concrete problem that live narration continues. The name and
spoken story memory use `shared_preferences` (browser `localStorage` on web). A returning
episode skips a new generic opening so its previous final beat remains the one
continued by the first live capture. The shared opening prompt is
`lib/assets/film-opening-prompt.json`; narrator-specific opening and live rules
are in `lib/assets/narrator-profiles.json`. Native and Netlify paths share both.
Speech preparation starts as soon as those credits arrive, during camera
consent. The camera button presents the credits on black while acquiring the
camera. A nine-second sequence fades the title in, holds it, fades to black,
then fades the separate director card in and out. After the final black pause,
the prepared opening plays and the camera fades in over three seconds on the
actual playback-start event. Live frames then prepare story narration during
the opening, through the same serialized
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
In debug builds (`flutter run -d chrome`), each narration logs once when playback
starts, including the opening. Filter the browser or Flutter console for
`[MCGEE narration]` and copy those lines when reporting a problem:

```text
[MCGEE narration] 2026-09-16T10:00:00.000Z [opening][morgan-freeman] I remembered when Ari...
```

The timestamp is the actual playback start in UTC. Unplayed drafts and subtitle
updates are not logged, and these narration logs are disabled in release builds.
The narrator voice is included so passages can be matched to their writing mode.

Keep the local function server running while QAing local changes. Editing local
prompt assets does not update any deployed function. The narration revision
header (`narration-stream-v2`) makes debug builds reject an incompatible server
before playback; the resolved debug backend URL identifies which server you
are actually testing. Restart the function server after shared prompt changes:
the revision is a compatibility check, not a hash of every prompt edit.
Build and deploy the web
app and functions together for release. Existing `build/web` and `.netlify`
artifacts can contain older prompts until rebuilt.

## Integration map

- `packages/narration_engine/`: provider-neutral engine, OpenRouter adapters,
  offline generator, and package tests.
- `lib/openrouter_runtime.dart`: the app's composition root. It owns one
  long-lived engine and the low-latency single-frame narration path.
- `lib/netlify_narration_renderer.dart`: fused web request/response adapter.
- `netlify/functions/narrate.mjs`: on-demand OpenRouter-to-Fish orchestration.
- `lib/audio_output.dart`: platform playback adapter; web MP3 streams use
  `lib/stream_audio_player_web.dart` and `web/narration_audio.js`, while existing
  byte/file tracks use `audioplayers`.
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

Narration invents one continuing fictional story, using a visible action,
posture, or object as an anchor for each beat. The opening establishes the selected mode’s
premise and stakes; the first live passage makes the camera detail part of that
same predicament. Subsequent passages develop attempts, complications, choices,
and payoffs from what was already spoken. An unchanged image can develop the
fictional dilemma; a camera cut does not reset it. Invented motives remain
fictional canon, separate from observed activity and real personal facts.

Each prompt carries recent spoken lines in order and singles out the last line
to continue. On the Netlify path, the writer also returns a cumulative story
recap, current visible activity, unresolved fictional thread, and recurring
elements. These become context for the next frame only when playback starts;
unspoken or discarded drafts cannot advance the story. Native builds retain the
bounded spoken history and rolling recap. The same editorial rules apply to all
five languages and both writers.

The narrator uses the character name, leaves three spoken passages without it,
then uses it again naturally in the ongoing action. This keeps occasional name
mentions without repeatedly introducing the character.
The Netlify writer retries a name-cadence violation once before TTS; a second
violation fails without speaking or saving the draft. Native writers reject a
violating draft before playback.

The package adapters default to `openai/gpt-5.6-terra`, used as a multimodal
writer in one pass with high reasoning effort. OpenRouter is asked to
rank providers by latency. Live passages are one 10–20-word sentence and are
discarded when their source frame is more than 20 seconds old, leaving enough
time for multimodal writing and speech synthesis. The Netlify path validates the complete
spoken sentence before speech synthesis; native builds can stream text into Fish
Audio while writing, with playback gated on the accepted final draft.
The host exposes exactly three narrator choices:

```dart
OpenRouterVoiceOption.morganFreeman     // Fish Audio
OpenRouterVoiceOption.davidAttenborough // Fish Audio
OpenRouterVoiceOption.jade              // Grok Voice TTS `eve`
```

The voice selection also selects the writing mode:

| Narrator | Opening | Subsequent narration |
| --- | --- | --- |
| Morgan Freeman | A fictional narrator recalled a specific problem, with a restrained hint of transcendence. | Everything remained in the past tense, as part of that recollection. |
| David Attenborough | A concrete wonder of nature leads to the named human animal. | Present-tense documentary observation treats visible behavior as the specimen’s survival tactics. |
| Eve (`jade` on the wire) | A grave fictional incident happening now ends with a live-feed handoff. | Present-tense reporting treats visible ordinary developments as an unfolding catastrophe. |

Switching voices stops active/queued narration and invalidates in-flight work,
then uses the new writing mode and TTS voice together. The spoken history stays;
the new mode governs tense and framing. Already prepared old-voice openings are
rejected. Returning episodes continue their saved story without a new opener.

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
npm run deploy
```

The deploy script runs JavaScript and Flutter tests, then builds fresh web assets
before publishing the app and functions together. A failed test or build stops
deployment, so an old `build/web` cannot accidentally be published by this command.

The offline generator reads `packages/narration_engine/.secrets/openrouter-key`
by default. That nested secret file is intentionally absent from Git; pass
`--api-key-file PATH` when the key lives elsewhere.

The private-circle web endpoint relies on its origin policy, per-IP rate limit,
and unadvertised deployment rather than an end-user login. Add real user
authentication before making the URL public. Do not embed shared provider
credentials in web assets or `--dart-define` values.
