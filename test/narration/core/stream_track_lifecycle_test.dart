import 'dart:async';
import 'dart:typed_data';

import 'package:mcgee/narration_engine.dart';
import 'package:test/test.dart';

void main() {
  test('disposing a stream track invokes cancellation only once', () async {
    final released = Completer<void>();
    var calls = 0;
    final track = AudioTrack.fromStream(
      id: 'stream',
      stream: const Stream<List<int>>.empty(),
      onCancel: () {
        calls += 1;
        return released.future;
      },
    );
    final first = track.dispose();
    final second = track.dispose();
    expect(identical(first, second), isTrue);
    expect(calls, 1);
    released.complete();
    await first;
    await track.dispose();
    expect(calls, 1);
  });

  test('disposes a renderer result that arrives after stop', () async {
    final renderer = _Renderer();
    final audio = _Audio();
    final track = _TrackedStream();
    final engine = _engine(renderer, audio);
    final outcome = engine.submit([_capture()]);
    await renderer.requested.future;
    await engine.stop();
    renderer.result.complete(_rendered(track.track));

    expect((await outcome).kind, NarrationOutcomeKind.silent);
    expect(track.cancellations, 1);
    expect(audio.playCalls, 0);
    expect(engine.memory.recentNarrations, isEmpty);
    await engine.close();
  });

  test('disposes a rendered stream rejected by editorial policy', () async {
    final renderer = _Renderer();
    final audio = _Audio();
    final track = _TrackedStream();
    final engine = _engine(renderer, audio);
    final outcome = engine.submit([_capture()]);
    await renderer.requested.future;
    renderer.result.complete(_rendered(
      track.track,
      text: List.filled(40, 'word').join(' '),
    ));

    expect((await outcome).kind, NarrationOutcomeKind.silent);
    expect(track.cancellations, 1);
    expect(audio.playCalls, 0);
    await engine.close();
  });

  test('disposes a rendered stream that became stale during generation', () async {
    final renderer = _Renderer();
    final audio = _Audio();
    final track = _TrackedStream();
    var now = DateTime.utc(2026);
    final engine = _engine(renderer, audio, clock: () => now);
    final outcome = engine.submit([_capture()]);
    await renderer.requested.future;
    now = now.add(const Duration(minutes: 1));
    renderer.result.complete(_rendered(track.track));

    expect((await outcome).kind, NarrationOutcomeKind.silent);
    expect(track.cancellations, 1);
    expect(audio.playCalls, 0);
    await engine.close();
  });

  test('streamed narration enters memory only when playback starts', () async {
    final renderer = _Renderer();
    final audio = _Audio();
    final track = _TrackedStream();
    final engine = _engine(renderer, audio);
    final outcome = engine.submit([_capture()]);
    await renderer.requested.future;
    renderer.result.complete(_rendered(track.track));
    await audio.requested.future;
    expect(engine.memory.recentNarrations, isEmpty);
    expect(track.cancellations, 0);

    final started = engine.events.firstWhere((event) => event is NarrationStarted);
    audio.start();
    await started;
    expect(engine.memory.recentNarrations.single.text, 'The subject advances.');
    expect(track.cancellations, 0);
    audio.finish();
    expect((await outcome).kind, NarrationOutcomeKind.spoken);
    await track.cancelled.future;
    expect(track.cancellations, 1);
    await engine.close();
  });

  test('stop aborts active and queued prepared streams exactly once', () async {
    final audio = _Audio();
    final engine = _engine(_Renderer(), audio);
    final first = _TrackedStream();
    final second = _TrackedStream();
    final opening = engine.speak('First line.', preparedTrack: first.track);
    await audio.requested.future;
    final started = engine.events.firstWhere((event) => event is NarrationStarted);
    audio.start();
    await started;
    final queued = engine.speak('Next line.', preparedTrack: second.track);
    await Future<void>.delayed(Duration.zero);
    await engine.stop();

    expect((await opening).kind, NarrationOutcomeKind.silent);
    expect((await queued).kind, NarrationOutcomeKind.silent);
    expect(first.cancellations, 1);
    expect(second.cancellations, 1);
    expect(engine.memory.recentNarrations.map((entry) => entry.text), ['First line.']);
    await engine.close();
  });

  test('superseded prepared stream is disposed without entering memory', () async {
    final audio = _Audio();
    final engine = _engine(_Renderer(), audio);
    final first = _TrackedStream();
    final replaced = _TrackedStream();
    final newest = _TrackedStream();
    final opening = engine.speak('First line.', preparedTrack: first.track);
    await audio.requested.future;
    audio.start();
    await Future<void>.delayed(Duration.zero);
    final old = engine.speak('Old line.', preparedTrack: replaced.track);
    await Future<void>.delayed(Duration.zero);
    final next = engine.speak('New line.', preparedTrack: newest.track);
    expect((await old).kind, NarrationOutcomeKind.silent);
    await replaced.cancelled.future;
    expect(replaced.cancellations, 1);
    expect(engine.memory.recentNarrations.map((entry) => entry.text), ['First line.']);
    await engine.stop();
    await opening;
    await next;
    await engine.close();
  });

  test('playback startup failure disposes stream without recording narration', () async {
    final audio = _Audio();
    final engine = _engine(_Renderer(), audio);
    final track = _TrackedStream();
    final outcome = engine.speak('An opening.', preparedTrack: track.track);
    await audio.requested.future;
    audio.startup.completeError(StateError('Audio decoder unavailable.'));
    expect((await outcome).kind, NarrationOutcomeKind.failed);
    await track.cancelled.future;
    expect(track.cancellations, 1);
    expect(engine.memory.recentNarrations, isEmpty);
    await engine.close();
  });

  test('failure after playback starts releases stream and retains spoken memory', () async {
    final audio = _Audio();
    final engine = _engine(_Renderer(), audio);
    final track = _TrackedStream();
    final outcome = engine.speak('An opening.', preparedTrack: track.track);
    await audio.requested.future;
    final started = engine.events.firstWhere((event) => event is NarrationStarted);
    audio.start();
    await started;
    audio.finished.completeError(StateError('Audio stream disconnected.'));
    expect((await outcome).kind, NarrationOutcomeKind.failed);
    await track.cancelled.future;
    expect(track.cancellations, 1);
    expect(engine.memory.recentNarrations.single.text, 'An opening.');
    await engine.close();
  });

  test('busy rejection disposes a host supplied stream', () async {
    final renderer = _Renderer();
    final engine = _engine(renderer, _Audio());
    final live = engine.submit([_capture()]);
    await renderer.requested.future;
    final track = _TrackedStream();
    final rejected = await engine.speak('An opening.', preparedTrack: track.track);
    expect(rejected.kind, NarrationOutcomeKind.silent);
    expect(track.cancellations, 1);
    await engine.stop();
    renderer.result.complete(_rendered(_TrackedStream().track));
    await live;
    await engine.close();
  });
}

NarrationEngine _engine(_Renderer renderer, _Audio audio, {Clock? clock}) {
  return NarrationEngine(
    sceneInterpreter: const DirectCaptureInterpreter(),
    narrator: _UnusedNarrator(),
    speechSynthesizer: _UnusedSpeech(),
    narrationRenderer: renderer,
    audioOutput: audio,
    policy: const NarrationPolicy(
      minimumGap: Duration.zero,
      rollingWindow: Duration.zero,
      sceneLookback: 0,
    ),
    clock: clock ?? () => DateTime.utc(2026),
  );
}

CapturedImage _capture() => CapturedImage(
  source: 'test',
  capturedAt: DateTime.utc(2026),
  bytes: Uint8List.fromList([1]),
);

RenderedNarration _rendered(AudioTrack track, {String text = 'The subject advances.'}) =>
    RenderedNarration(draft: NarrationDraft.speak(text), track: track);

final class _TrackedStream {
  _TrackedStream() {
    track = AudioTrack.fromStream(
      id: 'stream',
      stream: const Stream<List<int>>.empty(),
      onCancel: () async {
        cancellations += 1;
        cancelled.complete();
      },
    );
  }
  late final AudioTrack track;
  final cancelled = Completer<void>();
  int cancellations = 0;
}

final class _Renderer implements NarrationRenderer {
  final requested = Completer<void>();
  final result = Completer<RenderedNarration>();

  @override
  Future<RenderedNarration> render(NarrationRequest request) {
    requested.complete();
    return result.future;
  }
}

final class _UnusedNarrator implements NarrationModel {
  @override
  Future<NarrationDraft> narrate(NarrationRequest request) => throw UnimplementedError();
}

final class _UnusedSpeech implements SpeechSynthesizer {
  @override
  Future<AudioTrack> synthesize(String text) => throw UnimplementedError();
}

final class _Audio implements AudioOutput {
  final requested = Completer<void>();
  final startup = Completer<AudioPlayback>();
  final finished = Completer<void>();
  int playCalls = 0;

  @override
  Future<AudioPlayback> play(AudioTrack track) {
    playCalls += 1;
    requested.complete();
    return startup.future;
  }

  void start() => startup.complete(AudioPlayback(
    startedAt: DateTime.utc(2026),
    completed: finished.future,
  ));

  void finish() {
    if (!finished.isCompleted) finished.complete();
  }

  @override
  Future<void> stop() async => finish();
}
