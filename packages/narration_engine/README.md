# narration_engine

A Flutter-compatible Dart package that turns short, timestamped camera sequences
into occasional nature-documentary narration. The engine owns editorial pacing,
silence, continuity, repetition checks, cancellation, and playback sequencing.
The host app owns camera capture and device audio playback.

## Host app contract

The host saves captures as:

```text
captures/{source}/{unix-seconds}.jpg
```

For each narration attempt, pass a short window of `CapturedImage` objects to one
long-lived `NarrationEngine`. `capturedAt` is authoritative; the engine sorts the
window chronologically and keeps the newest four captures by default.

Each `CapturedImage` must have exactly one of `path` or `bytes`. Give every frame
the same `protagonistHint` when the recurring foreground camera holder should be
treated as the protagonist. This is scene guidance, not identity recognition.

```dart
final captures = <CapturedImage>[
  CapturedImage(
    id: '1789208310.jpg',
    source: 'webcam',
    capturedAt: DateTime.fromMillisecondsSinceEpoch(
      1789208310 * 1000,
      isUtc: true,
    ),
    path: 'captures/webcam/1789208310.jpg',
    protagonistHint: 'the recurring foreground camera holder',
  ),
  // More frames from the same short scene...
];
```

Camera sampling, retention, and file cleanup remain host-app responsibilities.

## Add the package

From this repository's Flutter host, use the checked-in package path:

```yaml
dependencies:
  narration_engine:
    path: packages/narration_engine
```

Import the provider-neutral API and web-safe OpenRouter adapters:

```dart
import 'package:narration_engine/narration_engine.dart';
import 'package:narration_engine/openrouter.dart';
```

## Create one engine per session

Keep the engine alive while the app is narrating a session or day. Recreating it
for every capture window discards recent observations, recurring motifs, spoken
lines, and fictional canon.

```dart
final openRouter = OpenRouterHttpClient(apiKey: keySuppliedByTheHost);

final engine = NarrationEngine(
  sceneInterpreter: const DirectCaptureInterpreter(),
  narrator: OpenRouterNarrationModel(
    client: openRouter,
    includeCaptures: true,
  ),
  speechSynthesizer: OpenRouterSpeechSynthesizer(client: openRouter),
  audioOutput: hostAudioOutput,
);
```

The current provider defaults are:

- Multimodal narration: `openai/gpt-5.6-sol`
- Speech: `fish-audio/s2.1-pro`
- Voice: `morgan-freeman`

Select a bundled voice without separately matching its provider model:

```dart
final speech = OpenRouterSpeechSynthesizer.withVoice(
  client: openRouter,
  voice: OpenRouterVoiceOption.morganFreeman,
);
```

Available presets are `morgan-freeman`, `david-attenborough`, and `jade`.
`OpenRouterVoiceOption.values` can populate a host-app selector. Morgan Freeman
and David Attenborough use Fish Audio S2.1 Pro; Jade uses Grok Voice TTS's
`eve` voice. Each preset keeps the required model and provider-specific voice
ID together.

All adapters can receive a different model or voice in their constructors. The
core remains provider-neutral through `SceneInterpreter`, `NarrationModel`,
`SpeechSynthesizer`, and `AudioOutput`.

On Dart IO, file-system helpers are available separately so importing
`openrouter.dart` stays browser-compatible:

```dart
import 'dart:io';

import 'package:narration_engine/openrouter_io.dart';

final key = await loadOpenRouterApiKey(File('.secrets/openrouter-key'));
```

On the web, the host must provide capture bytes and the key at runtime. The
MCGEE host uses a file picker and retains the selected key only in page memory.
Never add the key as a Flutter asset, source literal, browser-storage value, or
`--dart-define` value.

## Implement device playback

The Flutter host supplies an `AudioOutput` adapter for its chosen playback
package. OpenRouter currently returns an in-memory MP3 in `AudioTrack.bytes`.

`AudioOutput.play` must:

1. Start playback of the supplied track.
2. Return only after playback has actually started.
3. Set `AudioPlayback.startedAt` to that start time.
4. Provide a `completed` future that settles when playback finishes or fails.

`AudioOutput.stop` must stop active playback and be safe when nothing is playing.
The engine uses this contract to serialize speech and timestamp its events. Do
not complete `AudioPlayback.completed` immediately unless the adapter is an
offline file sink rather than audible playback.

## Submit capture windows

```dart
final outcome = await engine.submit(captures);

switch (outcome.kind) {
  case NarrationOutcomeKind.spoken:
    // Audio playback completed successfully.
    break;
  case NarrationOutcomeKind.silent:
    // Expected editorial result; inspect outcome.reason if useful for diagnostics.
    break;
  case NarrationOutcomeKind.failed:
    // Provider or playback failure; inspect outcome.error.
    break;
}
```

Silence is a successful result, not an error. The default policy suppresses stale,
low-salience, unchanged, overly frequent, overly long, and repetitive narration.
If `submit` is called while another submission is running, the new submission is
returned as silent by default. Live hosts can set `coalesceWhileBusy: true` to
retain one replaceable pending submission so the next pass uses the newest
capture without creating a stale queue.

Use capture timestamps close to the current time for the live engine. The default
maximum observation age is 30 seconds. Set
`NarrationPolicy(maximumObservationAge: null)` only for retrospective rendering
of saved captures.

## Observe events and manage lifecycle

```dart
final subscription = engine.events.listen((event) {
  switch (event) {
    case NarrationStarted():
      // Playback has started.
    case NarrationFinished():
      // Playback completed.
    case NarrationSkipped():
      // Policy, backpressure, cancellation, or model chose silence.
    case NarrationFailed():
      // Provider or playback failed.
  }
});

// Invalidate in-flight work and stop current audio, preserving continuity.
await engine.stop();

// Use this when starting an unrelated session or changing protagonist.
await engine.stop(clearMemory: true);

// At host teardown:
await subscription.cancel();
await engine.close();
openRouter.close();
```

`stop` cannot abort an HTTP request already handled by the platform client, but it
invalidates that request so a late result will not be narrated.

## Offline webcam smoke test

The repository includes three historical captures and a file-based `AudioOutput`
for validating the complete provider pipeline:

```sh
dart test
dart run bin/generate_webcam_track.dart
# Select a bundled voice for the generated track:
dart run bin/generate_webcam_track.dart --voice david
```

The command forces one spoken line, disables live staleness checks, and atomically
publishes a matched artifact pair:

```text
output/webcam/narration.mp3
output/webcam/manifest.json
```

This forced-speech behavior belongs only to the smoke-test command. Normal host
integration should leave `requireSpokenLine` false so silence remains available.
