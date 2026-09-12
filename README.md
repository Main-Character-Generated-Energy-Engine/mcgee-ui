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

Allow camera access when prompted. IO builds first try
`.secrets/openrouter-key`. Browsers cannot silently read host filesystem paths,
so the web app instead opens a text dialog where you can paste the key. The app
keeps the key in memory for the current page only. It does not print it, store
it in browser storage, package it as an asset, or compile it into the web
bundle.

The browser samples one JPEG every five seconds. After three new frames, it
submits the rolling window to the engine. The engine may speak or deliberately
stay silent. Spoken MP3 bytes are played through the host's `AudioOutput`
adapter, and the line is also shown as a subtitle.

Browser captures remain in memory because a web page cannot write the host file
contract directly. IO hosts use application support storage and save:

```text
captures/webcam/{unix-seconds}.jpg
```

Use localhost or HTTPS: browser camera access requires a secure context.

## Integration map

- `packages/narration_engine/`: provider-neutral engine, OpenRouter adapters,
  offline generator, and package tests.
- `lib/openrouter_runtime.dart`: the app's composition root. It owns one
  long-lived engine and a rolling three-capture window.
- `lib/audio_output.dart`: `audioplayers` implementation of `AudioOutput`.
- `lib/capture_store*.dart`: bytes in the browser; timestamped files on IO
  platforms.
- `lib/main.dart`: camera lifecycle, five-second sampling, key entry, and
  host UI only.

The host should keep one engine for a session so narrative memory, fictional
canon, repetition checks, pacing, and silence decisions survive between capture
windows. It should call `stop()` when capture pauses and `close()` at teardown.
Do not move camera ownership or audio playback into the package.

Defaults are OpenRouter vision `openai/gpt-4.1-mini`, comedy/editorial model
`openai/gpt-5.6-sol`, and Fish Audio S2.1 Pro with the Morgan Freeman preset.
The host exposes exactly three narrator choices:

```dart
OpenRouterVoiceOption.morganFreeman     // Fish Audio
OpenRouterVoiceOption.davidAttenborough // Fish Audio
OpenRouterVoiceOption.jade              // Grok Voice TTS `eve`
```

Each typed option keeps its provider model and voice ID paired. Never place a
raw voice ID, API key, or face-identification behavior in the core.

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

The offline generator reads `packages/narration_engine/.secrets/openrouter-key`
by default. That nested secret file is intentionally absent from Git; pass
`--api-key-file PATH` when the key lives elsewhere.

This client-only key flow is for the local MVP. Before public deployment, use a
restricted user-controlled OpenRouter key or an authentication design suitable
for untrusted clients. Do not embed a shared production credential in web
assets or `--dart-define` values.
