import 'dart:async';
import 'dart:typed_data';

import 'package:narration_engine/src/core/core.dart';
import 'package:test/test.dart';

void main() {
  group('NarrationEngine', () {
    test(
      'orders and bounds captures, then emits timestamped playback events',
      () async {
        final interpreter = _Interpreter(
          (_) async => const SceneObservation(
            description: 'A person makes coffee.',
            fingerprint: 'kitchen:coffee',
          ),
        );
        final narrator = _Narrator(
          (_) async => NarrationDraft.speak(
            'The creature begins its morning ritual.',
            motifs: const <String>['ritual'],
            canonUpdates: const <String, String>{
              'coffee': 'the source of morning courage',
            },
          ),
        );
        final synthesizer = _Synthesizer();
        final startedAt = DateTime.utc(2026, 1, 1, 9, 0, 5);
        final audio = _Audio(startedAt);
        final finishedAt = DateTime.utc(2026, 1, 1, 9, 0, 8);
        final engine = NarrationEngine(
          sceneInterpreter: interpreter,
          narrator: narrator,
          speechSynthesizer: synthesizer,
          audioOutput: audio,
          policy: const NarrationPolicy(minimumGap: Duration.zero),
          clock: () => finishedAt,
          maxCapturesPerObservation: 2,
        );
        final events = <NarrationEngineEvent>[];
        engine.events.listen(events.add);

        final first = _capture(0);
        final second = _capture(10);
        final third = _capture(20);
        final outcome = await engine.submit(<CapturedImage>[
          third,
          first,
          second,
        ]);

        expect(outcome.kind, NarrationOutcomeKind.spoken);
        expect(outcome.observedAt, third.capturedAt);
        expect(interpreter.received.single, <CapturedImage>[second, third]);
        expect(narrator.requests.single.captures, <CapturedImage>[
          second,
          third,
        ]);
        expect(synthesizer.texts, <String>[
          'The creature begins its morning ritual.',
        ]);
        expect(audio.playCount, 1);
        expect(events, hasLength(2));
        expect(events.first, isA<NarrationStarted>());
        expect(events.last, isA<NarrationFinished>());
        expect(events.first.observedAt, third.capturedAt);
        expect((events.first as NarrationStarted).playbackStartedAt, startedAt);
        expect(
          (events.last as NarrationFinished).playbackFinishedAt,
          finishedAt,
        );
        expect(engine.memory.canon['coffee'], 'the source of morning courage');
        await engine.close();
      },
    );

    test(
      'treats the narrator choosing silence as a successful silent outcome',
      () async {
        final narrator = _Narrator(
          (_) async => NarrationDraft.silence('The pause is funnier.'),
        );
        final synthesizer = _Synthesizer();
        final audio = _Audio(DateTime.utc(2026));
        final engine = _engine(
          narrator: narrator,
          synthesizer: synthesizer,
          audio: audio,
        );
        final events = <NarrationEngineEvent>[];
        engine.events.listen(events.add);

        final outcome = await engine.submit(<CapturedImage>[_capture(0)]);

        expect(outcome.kind, NarrationOutcomeKind.silent);
        expect(outcome.reason, 'The pause is funnier.');
        expect(synthesizer.texts, isEmpty);
        expect(audio.playCount, 0);
        expect(events.single, isA<NarrationSkipped>());
        await engine.close();
      },
    );

    test(
      'suppresses an unchanged scene before asking the narrator again',
      () async {
        final narrator = _Narrator(
          (_) async => NarrationDraft.speak('A rare expedition to the kettle.'),
        );
        final engine = _engine(narrator: narrator);

        final first = await engine.submit(<CapturedImage>[_capture(0)]);
        final second = await engine.submit(<CapturedImage>[_capture(60)]);

        expect(first.kind, NarrationOutcomeKind.spoken);
        expect(second.kind, NarrationOutcomeKind.silent);
        expect(second.reason, SilenceReason.unchangedScene.message);
        expect(narrator.requests, hasLength(1));
        await engine.close();
      },
    );

    test(
      'suppresses repeated copy even when the observed scene changes',
      () async {
        var interpretation = 0;
        final interpreter = _Interpreter(
          (_) async => SceneObservation(
            description: 'Moment $interpretation',
            fingerprint: 'scene-${interpretation++}',
          ),
        );
        final narrator = _Narrator(
          (_) async => NarrationDraft.speak('The creature seeks its reward.'),
        );
        final synthesizer = _Synthesizer();
        final engine = _engine(
          interpreter: interpreter,
          narrator: narrator,
          synthesizer: synthesizer,
        );

        await engine.submit(<CapturedImage>[_capture(0)]);
        final second = await engine.submit(<CapturedImage>[_capture(60)]);

        expect(second.kind, NarrationOutcomeKind.silent);
        expect(second.reason, SilenceReason.repeatedNarration.message);
        expect(synthesizer.texts, hasLength(1));
        await engine.close();
      },
    );

    test('drops a concurrent submission instead of queueing it', () async {
      final interpretation = Completer<SceneObservation>();
      final interpreter = _Interpreter((_) => interpretation.future);
      final engine = _engine(interpreter: interpreter);

      final first = engine.submit(<CapturedImage>[_capture(0)]);
      final second = await engine.submit(<CapturedImage>[_capture(1)]);

      expect(second.kind, NarrationOutcomeKind.silent);
      expect(second.reason, SilenceReason.busy.message);
      expect(interpreter.received, hasLength(1));

      interpretation.complete(
        const SceneObservation(
          description: 'A person waits.',
          fingerprint: 'waiting',
        ),
      );
      await first;
      await engine.close();
    });

    test(
      'coalesces busy submissions and prepares only the newest one',
      () async {
        final firstInterpretation = Completer<SceneObservation>();
        final interpreter = _Interpreter((captures) {
          if (captures.single.id == '0') return firstInterpretation.future;
          return Future<SceneObservation>.value(
            SceneObservation(
              description: 'Moment ${captures.single.id}',
              fingerprint: 'moment:${captures.single.id}',
            ),
          );
        });
        final narrator = _Narrator(
          (request) async => NarrationDraft.speak(
            'Moment ${request.captures.single.id} advances.',
          ),
        );
        final engine = NarrationEngine(
          sceneInterpreter: interpreter,
          narrator: narrator,
          speechSynthesizer: _Synthesizer(),
          audioOutput: _Audio(DateTime.utc(2026, 1, 1, 9, 0, 5)),
          policy: const NarrationPolicy(
            minimumGap: Duration.zero,
            sceneLookback: 0,
            rejectRepeatedNarration: false,
          ),
          clock: () => DateTime.utc(2026, 1, 1, 9, 0, 5),
          prefetchDuringPlayback: true,
          coalesceWhileBusy: true,
        );

        final first = engine.submit(<CapturedImage>[_capture(0)]);
        final replaced = engine.submit(<CapturedImage>[_capture(1)]);
        final newest = engine.submit(<CapturedImage>[_capture(2)]);

        expect((await replaced).kind, NarrationOutcomeKind.silent);
        firstInterpretation.complete(
          const SceneObservation(
            description: 'Moment 0',
            fingerprint: 'moment:0',
          ),
        );
        await Future.wait(<Future<NarrationOutcome>>[first, newest]);

        expect(
          interpreter.received.map((captures) => captures.single.id),
          <String>['0', '2'],
        );
        expect(
          narrator.requests.map((request) => request.captures.single.id),
          <String>['0', '2'],
        );
        await engine.close();
      },
    );

    test('close safely invalidates work still waiting on a provider', () async {
      final interpretation = Completer<SceneObservation>();
      final interpreter = _Interpreter((_) => interpretation.future);
      final engine = _engine(interpreter: interpreter);
      final emitted = <NarrationEngineEvent>[];
      engine.events.listen(emitted.add);

      final pending = engine.submit(<CapturedImage>[_capture(0)]);
      await engine.close();
      interpretation.complete(
        const SceneObservation(
          description: 'A moment that arrived too late.',
          fingerprint: 'late',
        ),
      );

      final outcome = await pending;
      expect(outcome.kind, NarrationOutcomeKind.silent);
      expect(emitted, isEmpty);
    });
  });

  group('NarrativeMemory', () {
    test('bounds observations, narrations, and canon', () {
      final memory = NarrativeMemory(
        maxObservations: 1,
        maxNarrations: 1,
        maxCanonEntries: 1,
      );
      memory
        ..recordObservation(
          const SceneObservation(description: 'one', fingerprint: 'one'),
        )
        ..recordObservation(
          const SceneObservation(description: 'two', fingerprint: 'two'),
        )
        ..recordNarration(
          text: 'first',
          observedAt: DateTime.utc(2026),
          canonUpdates: const <String, String>{'first': 'fact'},
        )
        ..recordNarration(
          text: 'second',
          observedAt: DateTime.utc(2026, 1, 2),
          canonUpdates: const <String, String>{'second': 'fact'},
        );

      expect(memory.snapshot.recentObservations.single.fingerprint, 'two');
      expect(memory.snapshot.recentNarrations.single.text, 'second');
      expect(memory.snapshot.canon, <String, String>{'second': 'fact'});
    });
  });

  test('policy rejects narration beyond its hard word limit', () {
    const policy = NarrationPolicy(maximumWords: 4);

    expect(
      policy.checkDraft(
        'The creature considers one final administrative migration.',
        const NarrativeMemorySnapshot(),
      ),
      SilenceReason.narrationTooLong,
    );
  });

  group('NarrationPolicy', () {
    test('enforces both minimum spacing and a rolling line limit', () {
      final memory = NarrativeMemory();
      final start = DateTime.utc(2026, 1, 1, 9);
      memory
        ..recordNarration(text: 'One.', observedAt: start)
        ..recordNarration(
          text: 'Two.',
          observedAt: start.add(const Duration(seconds: 40)),
        );
      const policy = NarrationPolicy(
        minimumGap: Duration(seconds: 20),
        rollingWindow: Duration(minutes: 2),
        maxNarrationsPerWindow: 2,
      );

      expect(
        policy.checkTiming(
          start.add(const Duration(seconds: 50)),
          memory.snapshot,
        ),
        SilenceReason.tooSoon,
      );
      expect(
        policy.checkTiming(
          start.add(const Duration(seconds: 70)),
          memory.snapshot,
        ),
        SilenceReason.rollingLimit,
      );
      expect(
        policy.checkTiming(
          start.add(const Duration(minutes: 3)),
          memory.snapshot,
        ),
        isNull,
      );
    });

    test('rejects observations that became stale during inference', () {
      const policy = NarrationPolicy(
        maximumObservationAge: Duration(seconds: 30),
      );
      final observedAt = DateTime.utc(2026, 1, 1, 9);

      expect(
        policy.checkStaleness(
          observedAt,
          observedAt.add(const Duration(seconds: 31)),
        ),
        SilenceReason.staleObservation,
      );
    });
  });

  test('default prompt carries restraint, continuity, and recent context', () {
    final builder = DocumentaryPromptBuilder(maximumWords: 24);
    final prompt = builder.build(
      observation: const SceneObservation(
        description: 'The protagonist reaches for a mug.',
        fingerprint: 'mug',
      ),
      memory: NarrativeMemorySnapshot(
        recentNarrations: <NarrationMemoryEntry>[
          NarrationMemoryEntry(
            text: 'Yesterday, the kettle won.',
            observedAt: DateTime.utc(2026),
            motifs: const <String>['rivalry'],
          ),
        ],
        canon: const <String, String>{'kettle': 'an old rival'},
      ),
    );

    expect(prompt, contains('at most 24 words'));
    expect(prompt, contains('Silence is a first-class editorial choice'));
    expect(prompt, contains('kettle: an old rival'));
    expect(prompt, contains('Yesterday, the kettle won.'));
    expect(prompt, contains('rivalry'));
  });

  test('capture and track reject ambiguous or empty payloads at runtime', () {
    expect(
      () => CapturedImage(source: 'webcam', capturedAt: DateTime.utc(2026)),
      throwsArgumentError,
    );
    expect(
      () => CapturedImage(
        source: 'webcam',
        capturedAt: DateTime.utc(2026),
        path: '',
      ),
      throwsArgumentError,
    );
    expect(() => AudioTrack(id: 'bad'), throwsArgumentError);
    expect(
      () => AudioTrack.fromBytes(id: 'empty', bytes: Uint8List(0)),
      throwsArgumentError,
    );
  });
}

CapturedImage _capture(int seconds) {
  return CapturedImage(
    id: '$seconds',
    source: 'webcam',
    capturedAt: DateTime.utc(2026, 1, 1, 9, 0, seconds),
    bytes: Uint8List.fromList(<int>[seconds]),
  );
}

NarrationEngine _engine({
  _Interpreter? interpreter,
  _Narrator? narrator,
  _Synthesizer? synthesizer,
  _Audio? audio,
}) {
  return NarrationEngine(
    sceneInterpreter:
        interpreter ??
        _Interpreter(
          (_) async => const SceneObservation(
            description: 'A person approaches the kettle.',
            fingerprint: 'kitchen:kettle',
          ),
        ),
    narrator:
        narrator ??
        _Narrator(
          (_) async => NarrationDraft.speak('The creature approaches.'),
        ),
    speechSynthesizer: synthesizer ?? _Synthesizer(),
    audioOutput: audio ?? _Audio(DateTime.utc(2026, 1, 1, 9, 0, 5)),
    policy: const NarrationPolicy(minimumGap: Duration.zero),
    clock: () => DateTime.utc(2026, 1, 1, 9, 0, 5),
  );
}

final class _Interpreter implements SceneInterpreter {
  _Interpreter(this.callback);

  final Future<SceneObservation> Function(List<CapturedImage>) callback;
  final List<List<CapturedImage>> received = <List<CapturedImage>>[];

  @override
  Future<SceneObservation> interpret(List<CapturedImage> captures) {
    received.add(captures);
    return callback(captures);
  }
}

final class _Narrator implements NarrationModel {
  _Narrator(this.callback);

  final Future<NarrationDraft> Function(NarrationRequest) callback;
  final List<NarrationRequest> requests = <NarrationRequest>[];

  @override
  Future<NarrationDraft> narrate(NarrationRequest request) {
    requests.add(request);
    return callback(request);
  }
}

final class _Synthesizer implements SpeechSynthesizer {
  final List<String> texts = <String>[];

  @override
  Future<AudioTrack> synthesize(String text) async {
    texts.add(text);
    return AudioTrack.fromLocation(
      id: 'track-${texts.length}',
      location: '/tmp/track.mp3',
    );
  }
}

final class _Audio implements AudioOutput {
  _Audio(this.startedAt);

  final DateTime startedAt;
  int playCount = 0;
  int stopCount = 0;

  @override
  Future<AudioPlayback> play(AudioTrack track) async {
    playCount += 1;
    return AudioPlayback(startedAt: startedAt, completed: Future<void>.value());
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
  }
}
