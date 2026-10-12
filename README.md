# MCGEE UI

Flutter camera narration app. OpenRouter writes short passages from camera
frames; Fish Audio `s2.1-pro-free` speaks them. There is no OpenRouter speech
fallback.

## Run

### Setup with mise

Install [mise](https://mise.jdx.dev/getting-started.html) 2026.10.3 or newer
and the [Flutter host prerequisites](https://docs.flutter.dev/install).
The toolchain declares Node 26.11.1 and Flutter 3.47.6
(including Dart). Matching host mise
installations are reused; missing versions are installed. Flutter archives and
checksums are configured for Linux x64, macOS x64/ARM64, and Windows x64.
Android and iOS development need their respective host toolchains.
Install the [GitHub CLI (`gh`)](https://cli.github.com/) on the host if you use
GitHub commands or agent workflows that require it; mise does not install it.
Deploying also needs the Netlify CLI in your global mise config
(`mise use --global npm:netlify-cli@latest`).

Enable [mise shell activation](https://mise.jdx.dev/shell-setup.html) once in
your shell's startup file, then open a new terminal:

| Shell | Startup file | Activation line |
| --- | --- | --- |
| Bash | `~/.bashrc` | `eval "$(mise activate bash)"` |
| Zsh | `~/.zshrc` | `eval "$(mise activate zsh)"` |
| Fish | `~/.config/fish/config.fish` | `mise activate fish &#124; source` |
| PowerShell | `$PROFILE` | `(&mise activate pwsh) &#124; Out-String &#124; Invoke-Expression` |

Activation automatically updates tool versions and the worktree environment
when you enter this checkout or another worktree. Use `mise doctor` to verify
that activation is enabled.

From the repository root in that terminal:

```sh
mise trust
mise install --locked
mise run setup
npm run dev
```

The app launches Chrome automatically; grant camera access when prompted.
The app and speech relay bind to `127.0.0.1`; the relay uses port 8767.
Run npm, Flutter, and browser commands directly.

To use your own browser at `http://localhost:8770`, add this optional preference
to the ignored `mise.local.toml`:

```toml
[env]
MCGEE_WEB_DEVICE = "web-server"
```

Browser testing uses your host's global Playwright CLI and browser caches; the
repository does not pin or install them.

Tool installations are shared across repositories in mise's host data directory.
The Node pin selects the shared Node installation and its bundled npm; it does
not install a separate npm per checkout. To use the same version outside this
repository, run `mise use --global node@26.11.1` once.

`mise.lock` records tool versions and Node/Flutter SDK checksums.
Existing installations outside mise can be registered with
`mise link <tool>@<version> /path/to/installation`.

To upgrade, edit the tool pins and Flutter archive URLs/checksums in `mise.toml`,
then regenerate the lockfile:

```sh
mise lock --platform linux-x64,macos-x64,macos-arm64,windows-x64
```

### VS Code

For VS Code opened from the desktop, set `dart.flutterSdkPath` in your VS Code
user settings to the absolute SDK directory printed by `mise where http:flutter`
from this checkout. Mise shims alone may not let the Dart/Flutter extension
discover the SDK. Reload VS Code and confirm the Flutter SDK version appears
in the status bar. Update this user setting when the Flutter pin changes.

### Agent sessions

Agent sessions are scoped to each worktree directory.
Sign-in and skills are shared across worktrees.

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

The existing setup tap unlocks the narration audio element before Flutter's
event queue, camera permission, and provider requests. The browser reuses that
element for every passage so Safari retains its playback permission. If a
browser still blocks playback, the prepared audio remains available to resume
from the error panel without another provider request.

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
server environment variable. Install the Netlify CLI in your global mise
config (`mise use --global npm:netlify-cli@latest`). Run `netlify login` and complete authentication in your
host browser, then run `netlify link` for a new checkout and
`npm run deploy`. That command
runs tests, builds the web app, and deploys the static assets with the speech
function. A web build embeds the OpenRouter key supplied at build time.
