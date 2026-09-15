import 'dart:async';
import 'dart:typed_data';

import 'package:narration_engine/narration_engine.dart';
import 'package:test/test.dart';

void main() {
  test('prepares action audio during an opening without overlapping playback', () async {
    final audio = _HeldAudio();
    final speech = _Speech();
    final narrator = _Narrator();
    final engine = _engine(audio, speech, narrator);
    final started = engine.events.firstWhere((event) => event is NarrationStarted);
    final openingTrack = _track('opening');
    final opening = engine.speak('An ordinary life, given extraordinary attention.',
        preparedTrack: openingTrack);
    await started;

    final live = engine.submit([_capture()]);
    await speech.prepared.future;
    await Future<void>.delayed(Duration.zero);

    expect(audio.tracks, [openingTrack]);
    expect(speech.texts, ['The subject rests a hand on the desk.']);
    expect(narrator.requests.single.memory.recentNarrations.single.text,
        'An ordinary life, given extraordinary attention.');

    audio.finish();
    expect((await opening).kind, NarrationOutcomeKind.spoken);
    await Future<void>.delayed(Duration.zero);
    expect(audio.tracks.map((track) => track.id), ['opening', 'action']);
    audio.finish();
    expect((await live).kind, NarrationOutcomeKind.spoken);
    await engine.close();
  });

  test('stopping the opening cancels queued action narration', () async {
    final audio = _HeldAudio();
    final speech = _Speech();
    final engine = _engine(audio, speech, _Narrator());
    final started = engine.events.firstWhere((event) => event is NarrationStarted);
    final opening = engine.speak('The opening.', preparedTrack: _track('opening'));
    await started;
    final live = engine.submit([_capture()]);
    await speech.prepared.future;
    await Future<void>.delayed(Duration.zero);

    await engine.stop();
    expect((await opening).kind, NarrationOutcomeKind.silent);
    expect((await live).kind, NarrationOutcomeKind.silent);
    expect(audio.tracks.map((track) => track.id), ['opening']);
    await engine.close();
  });
}

NarrationEngine _engine(_HeldAudio audio, _Speech speech, _Narrator narrator) {
  return NarrationEngine(
    sceneInterpreter: const DirectCaptureInterpreter(),
    narrator: narrator,
    speechSynthesizer: speech,
    audioOutput: audio,
    prefetchDuringPlayback: true,
    policy: const NarrationPolicy(
      minimumGap: Duration.zero,
      rollingWindow: Duration.zero,
      minimumSalience: 0,
      sceneLookback: 0,
    ),
    clock: () => DateTime.utc(2026),
  );
}

CapturedImage _capture() => CapturedImage(
  source: 'test',
  capturedAt: DateTime.utc(2026),
  bytes: Uint8List.fromList([1]),
);

AudioTrack _track(String id) => AudioTrack.fromBytes(
  id: id,
  bytes: Uint8List.fromList([1]),
);

final class _Narrator implements NarrationModel {
  final requests = <NarrationRequest>[];

  @override
  Future<NarrationDraft> narrate(NarrationRequest request) async {
    requests.add(request);
    return NarrationDraft.speak('The subject rests a hand on the desk.');
  }
}

final class _Speech implements SpeechSynthesizer {
  final texts = <String>[];
  final prepared = Completer<void>();

  @override
  Future<AudioTrack> synthesize(String text) async {
    texts.add(text);
    prepared.complete();
    return _track('action');
  }
}

final class _HeldAudio implements AudioOutput {
  final tracks = <AudioTrack>[];
  Completer<void>? _completion;

  @override
  Future<AudioPlayback> play(AudioTrack track) async {
    if (_completion != null) throw StateError('Overlapping playback');
    tracks.add(track);
    final completion = _completion = Completer<void>();
    return AudioPlayback(
      startedAt: DateTime.utc(2026),
      completed: completion.future,
    );
  }

  void finish() {
    final completion = _completion;
    _completion = null;
    completion?.complete();
  }

  @override
  Future<void> stop() async => finish();
}
