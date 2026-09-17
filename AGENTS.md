# Agent quickstart

Read `README.md` for setup, commands, architecture, and the browser test flow.
Work from the repository root; the launcher and mock server resolve files
relative to it.

- Use `npm run dev:e2e` for repeatable browser testing. It uses
  `test/fixtures/mock-camera-feed/` and requires no credentials or physical
  camera. Inspect
  `http://127.0.0.1:8767/__e2e/state` after the opening and live narration.
- Use `npm run dev:web` for real providers. Local keys belong in ignored
  `.secrets/` files or environment variables. Never print or commit them.
- Keep speech on Fish `s2.1-pro-free` for all voices. OpenRouter writes text;
  it is not a speech fallback. See `lib/src/openrouter/openrouter_voice_option.dart`
  and `netlify/functions/speech.mjs` for the model selection.
- Keep the browser audio response streaming: Fish body → relay body → Flutter
  stream → `web/narration_audio.js`. Do not collect the whole MP3 before
  playback. The local relay and Netlify function use the same speech handler.
- The web writer completes and validates each passage before speech. Native
  builds use Fish WebSocket; the web build uses HTTP streaming through the
  relay because Fish's raw TTS API is not directly callable from this browser
  app.
- Run focused tests for a change, then `npm test`, `flutter test`, and
  `npm run build:web` when changing the web speech path. `flutter analyze`
  checks Dart code.
