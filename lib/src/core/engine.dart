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
    NarrationRenderer? narrationRenderer,
    NarrationPromptBuilder promptBuilder = const DocumentaryPromptBuilder(),
    NarrationPolicy policy = const NarrationPolicy(),
    NarrativeMemory? memory,
    Clock? clock,
    Duration Function()? narrationPause,
    Future<void> Function(Duration)? delay,
    this.maxCapturesPerObservation = 4,
    this.prefetchDuringPlayback = false,
    this.coalesceWhileBusy = false,
  }) : assert(maxCapturesPerObservation > 0),
       _sceneInterpreter = sceneInterpreter,
       _narrator = narrator,
       _speechSynthesizer = speechSynthesizer,
       _audioOutput = audioOutput,
       _narrationRenderer = narrationRenderer,
       _promptBuilder = promptBuilder,
       _policy = policy,
       _memory = memory ?? NarrativeMemory(),
       _clock = clock ?? DateTime.now,
       _narrationPause = narrationPause ?? _noNarrationPause,
       _delay = delay ?? Future<void>.delayed;

  final SceneInterpreter _sceneInterpreter;
  final NarrationModel _narrator;
  final SpeechSynthesizer _speechSynthesizer;
  final AudioOutput _audioOutput;
  final NarrationRenderer? _narrationRenderer;
  final NarrationPromptBuilder _promptBuilder;
  final NarrationPolicy _policy;
  final NarrativeMemory _memory;
  final Clock _clock;
  final Duration Function() _narrationPause;
  final Future<void> Function(Duration) _delay;
  final int maxCapturesPerObservation;

  /// Allows one narration to be prepared while another is playing.
  ///
  /// Only the newest prepared narration is retained, so live narration cannot
  /// build an increasingly stale playback queue.
  final bool prefetchDuringPlayback;

  /// Retains only the newest submission received during model or TTS work.
  ///
  /// This is useful for live cameras: the next preparation starts from the
  /// freshest available frame instead of dropping every frame received while
  /// a provider request is in flight.
  final bool coalesceWhileBusy;

  final StreamController<NarrationEngineEvent> _events =
      StreamController<NarrationEngineEvent>.broadcast(sync: true);

  Object? _activePreparation;
  bool _closed = false;
  int _generation = 0;
  DateTime? _lastPlaybackFinishedAt;
  _QueuedNarration? _activeNarration;
  _QueuedNarration? _pendingNarration;
  _PendingSubmission? _pendingSubmission;
  bool _playbackLoopRunning = false;
  bool _isPlayingAudio = false;

  Stream<NarrationEngineEvent> get events => _events.stream;
  NarrativeMemorySnapshot get memory => _memory.snapshot;
  bool get isBusy =>
      _activePreparation != null ||
      _pendingSubmission != null ||
      _activeNarration != null ||
      _pendingNarration != null;
  bool get isPlaying => _isPlayingAudio;

  /// Processes the newest bounded window.
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

    // A prepared line that has not started playback is the next story beat,
    // but it is not in memory yet. Coalesce newer frames until that line is
    // spoken so they cannot be authored from the preceding story revision.
    if (_activePreparation != null ||
        _pendingNarration != null ||
        (_activeNarration != null && !_isPlayingAudio)) {
      if (coalesceWhileBusy) {
        final pending = _PendingSubmission(
          captures: window,
          observedAt: observedAt,
          generation: _generation,
        );
        final replaced = _pendingSubmission;
        _pendingSubmission = pending;
        if (replaced != null) {
          _completePendingSubmission(
            replaced,
            'A newer capture arrived before preparation began.',
          );
        }
        return pending.completed.future;
      }
      return _skip(window, observedAt, SilenceReason.busy.message);
    }
    if (!prefetchDuringPlayback &&
        (_activeNarration != null || _pendingNarration != null)) {
      return _skip(window, observedAt, SilenceReason.busy.message);
    }

    return _prepareSubmission(window, observedAt);
  }

  Future<NarrationOutcome> _prepareSubmission(
    List<CapturedImage> window,
    DateTime observedAt,
  ) async {
    final operationGeneration = _generation;
    final preparationToken = Object();
    _activePreparation = preparationToken;
    AudioTrack? ownedTrack;
    StreamingSpeechSynthesis? streamingSynthesis;
    Future<_TrackResult>? streamingTrack;
    var transferredTrack = false;
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
      // A frame captured while the opening was preparing may be older than
      // the opening's playback timestamp. Cadence applies when we prepare
      // this line; staleness is checked separately against capturedAt.
      final timingReason = _policy.checkTiming(now, _memory.snapshot);
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
      final NarrationDraft draft;
      final renderer = _narrationRenderer;
      if (renderer != null) {
        final rendered = await renderer.render(request);
        draft = rendered.draft;
        ownedTrack = rendered.track;
      } else if (_narrator case final StreamingNarrationModel streamingNarrator
          when _speechSynthesizer is StreamingSpeechSynthesizer) {
        final narrationStream = await streamingNarrator.narrateStream(request);
        streamingSynthesis = await _speechSynthesizer.synthesizeStream(
          narrationStream.textDeltas,
        );
        // Convert failures to values immediately so a fast TTS failure cannot
        // become an unhandled asynchronous error while narration is finishing.
        streamingTrack = streamingSynthesis.completed.then<_TrackResult>(
          _TrackSuccess.new,
          onError: (Object error, StackTrace stackTrace) =>
              _TrackFailure(error, stackTrace),
        );
        draft = await narrationStream.completed;
      } else {
        draft = await _narrator.narrate(request);
      }
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

      final AudioTrack track;
      if (ownedTrack case final renderedTrack?) {
        track = renderedTrack;
      } else if (streamingTrack case final streamingTrack?) {
        track = switch (await streamingTrack) {
          _TrackSuccess(:final track) => track,
          _TrackFailure(:final error, :final stackTrace) =>
            Error.throwWithStackTrace(error, stackTrace),
        };
      } else {
        track = await _speechSynthesizer.synthesize(text);
      }
      ownedTrack = track;
      if (!_isCurrent(operationGeneration)) {
        return _skip(window, observedAt, 'The engine was stopped.');
      }
      final playbackStaleness = _policy.checkStaleness(observedAt, _clock());
      if (playbackStaleness != null) {
        return _skip(window, observedAt, playbackStaleness.message);
      }

      final queued = _QueuedNarration(
        captures: window,
        observedAt: observedAt,
        text: text,
        motifs: draft.motifs,
        canonUpdates: draft.canonUpdates,
        track: track,
        generation: operationGeneration,
      );
      _enqueue(queued);
      transferredTrack = true;
      _releasePreparation(preparationToken);
      return await queued.completed.future;
    } catch (error) {
      if (!_isCurrent(operationGeneration)) {
        return _skip(window, observedAt, 'The engine was stopped.');
      }
      _emit(
        NarrationFailed(captures: window, observedAt: observedAt, error: error),
      );
      return NarrationOutcome.failed(observedAt: observedAt, error: error);
    } finally {
      if (!transferredTrack) {
        await _disposeTrack(ownedTrack);
        // A streaming-input synthesizer may finish after its draft is rejected.
        // Observe that result and release its track without delaying the skip.
        final abandonedTrack = streamingTrack;
        if (abandonedTrack != null) {
          unawaited(abandonedTrack.then((result) async {
            if (result case _TrackSuccess(:final track)) {
              await _disposeTrack(track);
            }
          }));
        }
        try {
          await streamingSynthesis?.cancel();
        } catch (_) {
          // Cancellation must not replace the original narration outcome.
        }
      }
      _releasePreparation(preparationToken);
    }
  }

  /// Synthesizes and queues a host-supplied line through the normal playback
  /// pipeline. This is useful for startup announcements that should hand off
  /// seamlessly to generated narration.
  /// A [preparedTrack] skips synthesis, allowing the host to prepare an opening
  /// before camera permission and start it only when its title card is ready.
  /// Ownership transfers to the engine even if the line is rejected.
  Future<NarrationOutcome> speak(String text, {AudioTrack? preparedTrack}) async {
    if (_closed) {
      await _disposeTrack(preparedTrack);
      throw StateError('The narration engine is closed.');
    }
    final spokenText = text.trim();
    if (spokenText.isEmpty) {
      await _disposeTrack(preparedTrack);
      throw ArgumentError.value(text, 'text', 'Must not be empty.');
    }

    final observedAt = _clock();
    const captures = <CapturedImage>[];
    if (_activePreparation != null) {
      await _disposeTrack(preparedTrack);
      return _skip(captures, observedAt, SilenceReason.busy.message);
    }

    final operationGeneration = _generation;
    final preparationToken = Object();
    _activePreparation = preparationToken;
    AudioTrack? ownedTrack = preparedTrack;
    var transferredTrack = false;
    try {
      final track =
          ownedTrack ?? await _speechSynthesizer.synthesize(spokenText);
      ownedTrack = track;
      if (!_isCurrent(operationGeneration)) {
        return _skip(captures, observedAt, 'The engine was stopped.');
      }

      final queued = _QueuedNarration(
        captures: captures,
        observedAt: observedAt,
        text: spokenText,
        motifs: const <String>[],
        canonUpdates: const <String, String>{},
        track: track,
        generation: operationGeneration,
      );
      _enqueue(queued);
      transferredTrack = true;
      _releasePreparation(preparationToken);
      return await queued.completed.future;
    } catch (error) {
      if (!_isCurrent(operationGeneration)) {
        return _skip(captures, observedAt, 'The engine was stopped.');
      }
      _emit(
        NarrationFailed(
          captures: captures,
          observedAt: observedAt,
          error: error,
        ),
      );
      return NarrationOutcome.failed(observedAt: observedAt, error: error);
    } finally {
      if (!transferredTrack) await _disposeTrack(ownedTrack);
      _releasePreparation(preparationToken);
    }
  }

  void _releasePreparation(Object preparationToken) {
    if (!identical(_activePreparation, preparationToken)) return;
    _activePreparation = null;

    _startPendingSubmissionIfReady();
  }

  void _startPendingSubmissionIfReady() {
    if (_activePreparation != null ||
        _pendingNarration != null ||
        (_activeNarration != null && !_isPlayingAudio)) {
      return;
    }

    final pending = _pendingSubmission;
    _pendingSubmission = null;
    if (pending == null) return;
    if (!_isCurrent(pending.generation)) {
      _completePendingSubmission(pending, 'The engine was stopped.');
      return;
    }
    unawaited(
      _prepareSubmission(pending.captures, pending.observedAt).then((outcome) {
        if (!pending.completed.isCompleted) {
          pending.completed.complete(outcome);
        }
      }),
    );
  }

  void _enqueue(_QueuedNarration narration) {
    final replaced = _pendingNarration;
    _pendingNarration = narration;
    if (replaced != null) {
      _completeSkipped(
        replaced,
        'A newer narration was ready before playback began.',
      );
    }
    if (!_playbackLoopRunning) {
      _playbackLoopRunning = true;
      unawaited(_drainPlaybackQueue());
    }
  }

  Future<void> _drainPlaybackQueue() async {
    while (!_closed) {
      final narration = _pendingNarration;
      if (narration == null) break;
      _pendingNarration = null;
      _activeNarration = narration;

      if (!_isCurrent(narration.generation)) {
        _completeSkipped(narration, 'The engine was stopped.');
        _activeNarration = null;
        _startPendingSubmissionIfReady();
        continue;
      }
      final queuedStaleness = _policy.checkStaleness(
        narration.observedAt,
        _clock(),
      );
      if (queuedStaleness != null) {
        _completeSkipped(narration, queuedStaleness.message);
        _activeNarration = null;
        _startPendingSubmissionIfReady();
        continue;
      }

      StreamSubscription<AudioPlaybackProgress>? playbackProgressSubscription;
      var playedSuccessfully = false;
      try {
        final playback = await _audioOutput.play(narration.track);
        if (!_isCurrent(narration.generation)) {
          await _audioOutput.stop();
          _isPlayingAudio = false;
          _completeSkipped(narration, 'The engine was stopped.');
          _activeNarration = null;
          continue;
        }

        _isPlayingAudio = true;
        playbackProgressSubscription = playback.progress.listen((progress) {
          if (!_isCurrent(narration.generation) ||
              !identical(_activeNarration, narration)) {
            return;
          }
          _emit(
            NarrationProgress(
              captures: narration.captures,
              observedAt: narration.observedAt,
              text: narration.text,
              position: progress.position,
              duration: progress.duration,
            ),
          );
        });
        _memory.recordNarration(
          text: narration.text,
          observedAt: narration.observedAt,
          motifs: narration.motifs,
          canonUpdates: narration.canonUpdates,
        );
        // The line is now part of the canonical spoken story. A coalesced
        // frame may safely use it as the immediate predecessor.
        _startPendingSubmissionIfReady();
        _emit(
          NarrationStarted(
            captures: narration.captures,
            observedAt: narration.observedAt,
            playbackStartedAt: playback.startedAt,
            text: narration.text,
          ),
        );
        await playback.completed;
        _isPlayingAudio = false;
        if (!_isCurrent(narration.generation)) {
          _completeSkipped(narration, 'The engine was stopped.');
          _activeNarration = null;
          continue;
        }

        final playbackFinishedAt = _clock();
        _lastPlaybackFinishedAt = playbackFinishedAt;
        _emit(
          NarrationFinished(
            captures: narration.captures,
            observedAt: narration.observedAt,
            playbackStartedAt: playback.startedAt,
            playbackFinishedAt: playbackFinishedAt,
            text: narration.text,
          ),
        );
        if (identical(_activeNarration, narration)) {
          _activeNarration = null;
        }
        if (!narration.completed.isCompleted) {
          narration.completed.complete(
            NarrationOutcome.spoken(
              observedAt: narration.observedAt,
              playbackStartedAt: playback.startedAt,
              text: narration.text,
            ),
          );
        }
        playedSuccessfully = true;
      } catch (error) {
        _isPlayingAudio = false;
        if (_isCurrent(narration.generation)) {
          _emit(
            NarrationFailed(
              captures: narration.captures,
              observedAt: narration.observedAt,
              error: error,
            ),
          );
          if (identical(_activeNarration, narration)) {
            _activeNarration = null;
          }
          if (!narration.completed.isCompleted) {
            narration.completed.complete(
              NarrationOutcome.failed(
                observedAt: narration.observedAt,
                error: error,
              ),
            );
          }
        } else {
          _completeSkipped(narration, 'The engine was stopped.');
        }
      } finally {
        await _disposeTrack(narration.track);
        await playbackProgressSubscription?.cancel();
        _isPlayingAudio = false;
        if (identical(_activeNarration, narration)) {
          _activeNarration = null;
        }
        // If playback failed before the line entered memory, continue from
        // the last line that really was spoken.
        _startPendingSubmissionIfReady();
      }
      if (playedSuccessfully && !_closed) {
        final pause = _narrationPause();
        if (!pause.isNegative && pause > Duration.zero) await _delay(pause);
      }
    }

    _playbackLoopRunning = false;
    if (!_closed && _pendingNarration != null) {
      _playbackLoopRunning = true;
      unawaited(_drainPlaybackQueue());
    }
  }

  void _completeSkipped(_QueuedNarration narration, String reason) {
    unawaited(_disposeTrack(narration.track));
    if (narration.completed.isCompleted) return;
    narration.completed.complete(
      _skip(narration.captures, narration.observedAt, reason),
    );
  }

  void _completePendingSubmission(
    _PendingSubmission submission,
    String reason,
  ) {
    if (submission.completed.isCompleted) return;
    submission.completed.complete(
      _skip(submission.captures, submission.observedAt, reason),
    );
  }

  /// Invalidates in-flight work and stops active audio.
  Future<void> stop({bool clearMemory = false}) async {
    _generation += 1;
    _activePreparation = null;
    final pendingSubmission = _pendingSubmission;
    _pendingSubmission = null;
    if (pendingSubmission != null) {
      _completePendingSubmission(pendingSubmission, 'The engine was stopped.');
    }
    final pending = _pendingNarration;
    _pendingNarration = null;
    if (pending != null) {
      _completeSkipped(pending, 'The engine was stopped.');
    }
    final active = _activeNarration;
    if (active != null) {
      _completeSkipped(active, 'The engine was stopped.');
    }
    // Abort streamed producers before waiting on a player that may still be
    // waiting for its first chunk. Disposing is safe if playback also finishes.
    await Future.wait<void>([
      _disposeTrack(pending?.track),
      _disposeTrack(active?.track),
      _audioOutput.stop(),
    ]);
    _isPlayingAudio = false;
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

  Future<void> _disposeTrack(AudioTrack? track) async {
    try {
      await track?.dispose();
    } catch (_) {
      // Resource cleanup must not fail the playback loop or hide its outcome.
    }
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

Duration _noNarrationPause() => Duration.zero;

final class _PendingSubmission {
  _PendingSubmission({
    required this.captures,
    required this.observedAt,
    required this.generation,
  });

  final List<CapturedImage> captures;
  final DateTime observedAt;
  final int generation;
  final Completer<NarrationOutcome> completed = Completer<NarrationOutcome>();
}

final class _QueuedNarration {
  _QueuedNarration({
    required this.captures,
    required this.observedAt,
    required this.text,
    required this.motifs,
    required this.canonUpdates,
    required this.track,
    required this.generation,
  });

  final List<CapturedImage> captures;
  final DateTime observedAt;
  final String text;
  final List<String> motifs;
  final Map<String, String> canonUpdates;
  final AudioTrack track;
  final int generation;
  final Completer<NarrationOutcome> completed = Completer<NarrationOutcome>();
}

sealed class _TrackResult {}

final class _TrackSuccess implements _TrackResult {
  const _TrackSuccess(this.track);

  final AudioTrack track;
}

final class _TrackFailure implements _TrackResult {
  const _TrackFailure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}
