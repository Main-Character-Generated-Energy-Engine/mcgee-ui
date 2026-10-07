# MCGEE UI

Flutter camera narration app. OpenRouter writes short passages from camera
frames; Fish Audio `s2.1-pro-free` speaks them. There is no OpenRouter speech
fallback.

## Run

### Devcontainer (web development)

Install Docker and the VS Code Dev Containers extension. Open this repository
in VS Code and run **Dev Containers: Reopen in Container**. The container installs
Flutter 3.47.6 (including Dart), Node.js 24.19.0, and Netlify CLI 27.11.2,
enables web support, and runs `flutter pub get`. No host Flutter or Node.js
installation is needed.
Flutter comes from the official prebuilt Linux SDK archive, verified against
its SHA-256 checksum. The image uses x64; ARM hosts (including Apple Silicon)
run it through Docker's emulation.

Codex and Claude Code extensions are installed in the container. Their state
is stored on the host in `~/.agent-state/mcgee-narrator/codex` and
`~/.agent-state/mcgee-narrator/claude`, mounted at `/home/node/.codex` and
`/home/node/.claude`. Sessions and file-based sign-ins survive container
rebuilds. VS Code's server state is persisted in `~/.vscode-server`, with
workspace state in `~/.vscode-server-workspaces/mcgee-narrator`, following
aricatadora's devcontainer layout. The workspace-specific directory names use
the checkout folder's basename. These directories are created automatically
on the host before the container starts.

Configure the provider keys below, run `npm run dev` in the container terminal, then open
`http://localhost:8770` in your host browser. Ports 8770 (app) and 8767
(speech relay) are forwarded to the same local port numbers; keep both
ports free on the host.

Grant camera access in your host browser. The container uses
Flutter's `web-server` device instead of launching Chrome inside the container.
Browser playback, camera access, and the localhost provider endpoints use the
forwarded ports. Keep the forwards private and access the app through localhost.

Tests, analysis, and web builds also run in the container terminal. This setup
targets web development; it does not include Android or iOS toolchains. Change
the pinned versions in `.devcontainer/Dockerfile` and rebuild the container
when upgrading. Update the Flutter archive checksum alongside its version.

### Host development

Alternatively, install Flutter (with Chrome support) and Node.js on the host,
then run `flutter pub get`. The host launcher opens Chrome for `npm run dev`.
To serve the app in your own browser instead, set `MCGEE_WEB_DEVICE=web-server`.
`MCGEE_DEV_HOST` controls the app and relay bind address (default `127.0.0.1`;
the devcontainer sets `0.0.0.0`).

### Provider credentials

Set `OPENROUTER_API_KEY` and `FISH_AUDIO_API_KEY`, or put each key in its
ignored local file:

```text
.secrets/openrouter-key
.secrets/fishaudio-key
```

| Command | Purpose |
| --- | --- |
| `npm run dev` | Run the web app and a local Fish speech relay on port 8767. |
| `node scripts/web.mjs check` | Check local credentials without printing them. |
| `npm run build:web` | Build release assets in `build/web`. |
| `npm run test` | Run the JavaScript and Flutter test suites. |
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

## Manual browser end-to-end test

For a manual browser check without credentials or a physical camera, run
`node scripts/web.mjs e2e` and open `http://localhost:8770`.
Enter a name and press Enter, then press Enter on the
camera consent screen. The app cycles through
`test/fixtures/mock-camera-feed/1.jpg` to `4.jpg` every two seconds. Local mock
OpenRouter and Fish responses exercise
the opening, live narration, speech request, and browser playback paths. Check
`http://127.0.0.1:8767/__e2e/state` for request counts and `distinctFrames`;
the latter should increase as live narration uses different camera images.
This mode is enabled only by launcher supplied Dart defines.
Set `MOCK_FISH_DELAY_MS=30000` when running `node scripts/web.mjs e2e` to exercise the
five-second opening warning and late audio recovery.

## Narration quality evaluation

Run `dart run scripts/eval_narration.dart` from the repository root with the
local OpenRouter key configured as above. This uses the real text provider
and incurs provider usage; it does not request speech. Optional arguments
`morgan-freeman`, `david-attenborough`, or `jade` select a single narrator.

By default, the evaluation generates an opening and thirteen passages using
one unchanged image with no handheld object. Fixtures are test inputs only;
production prompts contain no fixture-derived objects or physical attributes.
Use `--scenario=stale-object` to seed deliberately wrong object-based history,
or `--scenario=object-exits` to show an object once and then remove it.
Use `--scenario=stale-drive` with David to check migration from an old feeding
thread to the current courtship arc. Use `--scenario=stale-strategy` to
check that a resolved, repetitive action is retired when the next arc starts. Use
`--passages=6` for a single arc. These cases check that current visual evidence
overrides saved claims, while the underlying narrative can continue.

Text and canon updates are saved in ignored `.dart_tool/narration-eval.json`
for manual review. The evaluator records requested arc stages and flags stage
mismatches and possible unsupported object references. Each six-passage episode
should make its goal, tactic, snag, response, choice, and limited payoff audible.
David develops scene-supported reproductive strategies. Each new arc must
move beyond the recently resolved tactics; refining the same action counts as
repetition. Story state retains the last three resolved strategies. Biological labels
should stay occasional; older saved drives are replaced by reproduction.
Physical outcomes require current visual evidence. Review repetition, sentence
structure, and contrastive negation. The mock browser flow verifies integration
separately; it does not evaluate prose quality.

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

Opening writing has a 30-second deadline and speech has a separate 60-second
startup deadline. If playback has not started five seconds after the opening
titles fade out, an extra title card appears. At fifteen seconds the app
explains the delay and offers a return to narration selection. The camera
stays hidden until opening playback begins. Debug logs show writing, first
audio, title fade, playback delay, and any failed stage.

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
server environment variable. The devcontainer includes the Netlify CLI; for
host development, install it separately. Run `netlify login` in your development
terminal and complete authentication in your host browser, then run
`netlify link` for a new checkout and `npm run deploy`. That command
runs tests, builds the web app, and deploys the static assets with the speech
function. A web build embeds the OpenRouter key supplied at build time.
