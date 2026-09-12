// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'contracts.dart';
import 'memory.dart';
import 'models.dart';
import 'policy.dart';
import 'prompt_builder.dart';

/// Coordinates interpretation, editorial choice, narration, TTS, and playback.
final class NarrationEngine {
  NarrationEngine({
    required SceneInterpreter sceneInterpreter,
    required NarrationModel narrator,
    required SpeechSynthesizer speechSynthesizer,
    required AudioOutput audioOutput,
    NarrationPromptBuilder promptBuilder = const DocumentaryPromptBuilder(),
    NarrationPolicy policy = const NarrationPolicy(),
    NarrativeMemory? memory,
    Clock? clock,
    this.maxCapturesPerObservation = 4,
  }) : assert(maxCapturesPerObservation > 0),
       _sceneInterpreter = sceneInterpreter,
       _narrator = narrator,
       _speechSynthesizer = speechSynthesizer,
       _audioOutput = audioOutput,
       _promptBuilder = promptBuilder,
       _policy = policy,
       _memory = memory ?? NarrativeMemory(),
       _clock = clock ?? DateTime.now;

  final SceneInterpreter _sceneInterpreter;
  final NarrationModel _narrator;
  final SpeechSynthesizer _speechSynthesizer;
  final AudioOutput _audioOutput;
  final NarrationPromptBuilder _promptBuilder;
  final NarrationPolicy _policy;
  final NarrativeMemory _memory;
  final Clock _clock;
  final int maxCapturesPerObservation;

  final StreamController<NarrationEngineEvent> _events =
      StreamController<NarrationEngineEvent>.broadcast(sync: true);

  bool _busy = false;
  bool _closed = false;
  int _generation = 0;
  DateTime? _lastPlaybackFinishedAt;

  Stream<NarrationEngineEvent> get events => _events.stream;
  NarrativeMemorySnapshot get memory => _memory.snapshot;
  bool get isBusy => _busy;

  /// Processes the newest bounded window, dropping a submission if busy.
  ///
  /// Capture timestamps determine ordering. The newest timestamp is propagated
  /// as `observedAt` on every outcome and event.
  Future<NarrationOutcome> submit(Iterable<CapturedImage> captures) async {
    if (_closed) {
      throw StateError('The narration engine is closed.');
    }
    final ordered = captures.toList()
      ..sort((left, right) => left.capturedAt.compareTo(right.capturedAt));
    if (ordered.isEmpty) {
      throw ArgumentError.value(captures, 'captures', 'Must not be empty.');
    }
    final window = List<CapturedImage>.unmodifiable(
      ordered.length <= maxCapturesPerObservation
          ? ordered
          : ordered.sublist(ordered.length - maxCapturesPerObservation),
    );
    final observedAt = window.last.capturedAt;

    if (_busy) {
      return _skip(window, observedAt, SilenceReason.busy.message);
    }

    _busy = true;
    final operationGeneration = _generation;
    try {
      final now = _clock();
      final lastPlaybackFinishedAt = _lastPlaybackFinishedAt;
      if (lastPlaybackFinishedAt != null) {
        final sincePlayback = now.difference(lastPlaybackFinishedAt);
        if (!sincePlayback.isNegative && sincePlayback < _policy.minimumGap) {
          return _skip(window, observedAt, SilenceReason.tooSoon.message);
        }
      }
      final initialStaleness = _policy.checkStaleness(observedAt, now);
      if (initialStaleness != null) {
        return _skip(window, observedAt, initialStaleness.message);
      }
      final timingReason = _policy.checkTiming(observedAt, _memory.snapshot);
      if (timingReason != null) {
        return _skip(window, observedAt, timingReason.message);
      }

      final observation = await _sceneInterpreter.interpret(window);
      if (!_isCurrent(operationGeneration)) {
        return _skip(window, observedAt, 'The engine was stopped.');
      }

      final observationReason = _policy.checkObservation(
        observation,
        _memory.snapshot,
      );
      _memory.recordObservation(observation);
      if (observationReason != null) {
        return _skip(window, observedAt, observationReason.message);
      }

      final snapshot = _memory.snapshot;
      final request = NarrationRequest(
        prompt: _promptBuilder.build(
          observation: observation,
          memory: snapshot,
        ),
        observation: observation,
        captures: window,
        memory: snapshot,
      );
      final draft = await _narrator.narrate(request);
      if (!_isCurrent(operationGeneration)) {
        return _skip(window, observedAt, 'The engine was stopped.');
      }
      if (!draft.shouldSpeak) {
        return _skip(
          window,
          observedAt,
          draft.reason ?? SilenceReason.narratorChoseSilence.message,
        );
      }

      final text = draft.text?.trim() ?? '';
      final draftReason = _policy.checkDraft(text, _memory.snapshot);
      if (draftReason != null) {
        return _skip(window, observedAt, draftReason.message);
      }

      final finalStaleness = _policy.checkStaleness(observedAt, _clock());
      if (finalStaleness != null) {
        return _skip(window, observedAt, finalStaleness.message);
      }

      final track = await _speechSynthesizer.synthesize(text);
      if (!_isCurrent(operationGeneration)) {
        return _skip(window, observedAt, 'The engine was stopped.');
      }
      final playbackStaleness = _policy.checkStaleness(observedAt, _clock());
      if (playbackStaleness != null) {
        return _skip(window, observedAt, playbackStaleness.message);
      }
      final playback = await _audioOutput.play(track);
      if (!_isCurrent(operationGeneration)) {
        await _audioOutput.stop();
        return _skip(window, observedAt, 'The engine was stopped.');
      }

      _memory.recordNarration(
        text: text,
        observedAt: observedAt,
        motifs: draft.motifs,
        canonUpdates: draft.canonUpdates,
      );
      _emit(
        NarrationStarted(
          captures: window,
          observedAt: observedAt,
          playbackStartedAt: playback.startedAt,
          text: text,
        ),
      );
      await playback.completed;
      if (!_isCurrent(operationGeneration)) {
        return _skip(window, observedAt, 'The engine was stopped.');
      }
      final playbackFinishedAt = _clock();
      _lastPlaybackFinishedAt = playbackFinishedAt;
      _emit(
        NarrationFinished(
          captures: window,
          observedAt: observedAt,
          playbackStartedAt: playback.startedAt,
          playbackFinishedAt: playbackFinishedAt,
          text: text,
        ),
      );
      return NarrationOutcome.spoken(
        observedAt: observedAt,
        playbackStartedAt: playback.startedAt,
        text: text,
      );
    } catch (error) {
      if (!_isCurrent(operationGeneration)) {
        return _skip(window, observedAt, 'The engine was stopped.');
      }
      _emit(
        NarrationFailed(captures: window, observedAt: observedAt, error: error),
      );
      return NarrationOutcome.failed(observedAt: observedAt, error: error);
    } finally {
      _busy = false;
    }
  }

  /// Invalidates in-flight work and stops active audio.
  Future<void> stop({bool clearMemory = false}) async {
    _generation += 1;
    await _audioOutput.stop();
    if (clearMemory) {
      _memory.clear();
      _lastPlaybackFinishedAt = null;
    }
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await stop();
    await _events.close();
  }

  bool _isCurrent(int operationGeneration) {
    return !_closed && operationGeneration == _generation;
  }

  NarrationOutcome _skip(
    List<CapturedImage> captures,
    DateTime observedAt,
    String reason,
  ) {
    if (!_events.isClosed) {
      _emit(
        NarrationSkipped(
          captures: captures,
          observedAt: observedAt,
          reason: reason,
        ),
      );
    }
    return NarrationOutcome.silent(observedAt: observedAt, reason: reason);
  }

  void _emit(NarrationEngineEvent event) {
    if (!_closed && !_events.isClosed) {
      _events.add(event);
    }
  }
}
