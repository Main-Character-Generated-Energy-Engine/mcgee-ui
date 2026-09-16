import 'dart:async';
import 'dart:typed_data';

/// An image supplied by the host application.
///
/// Exactly one of [path] and [bytes] must be provided. The engine treats the
/// capture time as authoritative and never derives it from the file name.
final class CapturedImage {
  CapturedImage({
    required this.source,
    required this.capturedAt,
    this.path,
    this.bytes,
    this.protagonistHint,
    String? id,
  }) : id = id ?? '$source:${capturedAt.toUtc().toIso8601String()}' {
    if ((path == null) == (bytes == null)) {
      throw ArgumentError('Provide exactly one of path or bytes.');
    }
    if (path?.trim().isEmpty ?? false) {
      throw ArgumentError.value(path, 'path', 'Must not be empty.');
    }
    if (bytes?.isEmpty ?? false) {
      throw ArgumentError.value(bytes, 'bytes', 'Must not be empty.');
    }
  }

  final String id;
  final String source;
  final DateTime capturedAt;
  final String? path;
  final Uint8List? bytes;

  /// Optional host context such as "the recurring foreground camera holder".
  /// This is descriptive guidance, not an identity or face-recognition result.
  final String? protagonistHint;
}

/// A provider-neutral account of what happened across a capture window.
final class SceneObservation {
  const SceneObservation({
    required this.description,
    required this.fingerprint,
    this.salience = 1,
    this.details = const <String, String>{},
  }) : assert(salience >= 0 && salience <= 1);

  /// A short, literal description suitable for a narration prompt.
  final String description;

  /// A stable, terse identifier used to suppress unchanged scenes.
  final String fingerprint;

  /// Provider-estimated narrative significance, from 0 to 1.
  final double salience;

  /// Optional structured facts such as action, setting, or visible objects.
  final Map<String, String> details;
}

/// An immutable view of recent narrative history passed to providers.
final class NarrativeMemorySnapshot {
  const NarrativeMemorySnapshot({
    this.recentObservations = const <SceneObservation>[],
    this.recentNarrations = const <NarrationMemoryEntry>[],
    this.canon = const <String, String>{},
    this.storySummary = '',
  });

  final List<SceneObservation> recentObservations;
  final List<NarrationMemoryEntry> recentNarrations;
  final Map<String, String> canon;

  /// Bounded recap of spoken beats older than [recentNarrations].
  final String storySummary;
}

final class NarrationMemoryEntry {
  const NarrationMemoryEntry({
    required this.text,
    required this.observedAt,
    this.motifs = const <String>[],
  });

  final String text;
  final DateTime observedAt;
  final List<String> motifs;
}

final class NarrationRequest {
  const NarrationRequest({
    required this.prompt,
    required this.observation,
    required this.captures,
    required this.memory,
  });

  final String prompt;
  final SceneObservation observation;
  final List<CapturedImage> captures;
  final NarrativeMemorySnapshot memory;
}

/// The narrator may explicitly choose silence; that is a successful result.
final class NarrationDraft {
  const NarrationDraft._({
    required this.shouldSpeak,
    this.text,
    this.reason,
    this.motifs = const <String>[],
    this.canonUpdates = const <String, String>{},
  });

  factory NarrationDraft.speak(
    String text, {
    List<String> motifs = const <String>[],
    Map<String, String> canonUpdates = const <String, String>{},
  }) {
    return NarrationDraft._(
      shouldSpeak: true,
      text: text,
      motifs: motifs,
      canonUpdates: canonUpdates,
    );
  }

  factory NarrationDraft.silence([String? reason]) {
    return NarrationDraft._(shouldSpeak: false, reason: reason);
  }

  final bool shouldSpeak;
  final String? text;
  final String? reason;
  final List<String> motifs;
  final Map<String, String> canonUpdates;
}

/// A narration whose spoken text is available before generation completes.
///
/// [textDeltas] is single-subscription and preserves provider order. The
/// [completed] future returns the same text as a regular [NarrationDraft] after
/// the stream ends. Low-latency implementations may leave narrative metadata
/// empty so speech can begin without waiting for a structured second pass.
final class NarrationTextStream {
  const NarrationTextStream({
    required this.textDeltas,
    required this.completed,
  });

  final Stream<String> textDeltas;
  final Future<NarrationDraft> completed;
}

/// A validated narration and its already-synthesized audio track.
final class RenderedNarration {
  RenderedNarration({required this.draft, required this.track}) {
    if (!draft.shouldSpeak || (draft.text?.trim().isEmpty ?? true)) {
      throw ArgumentError.value(
        draft,
        'draft',
        'A rendered narration must contain spoken text.',
      );
    }
  }

  final NarrationDraft draft;
  final AudioTrack track;
}

/// Synthesized audio, represented either in memory or by a provider location.
final class AudioTrack {
  AudioTrack({required this.id, this.bytes, this.location, this.duration}) {
    if ((bytes == null) == (location == null)) {
      throw ArgumentError('Provide exactly one of bytes or location.');
    }
    if (bytes?.isEmpty ?? false) {
      throw ArgumentError.value(bytes, 'bytes', 'Must not be empty.');
    }
    if (location?.trim().isEmpty ?? false) {
      throw ArgumentError.value(location, 'location', 'Must not be empty.');
    }
  }

  /// Creates a track backed by in-memory audio.
  factory AudioTrack.fromBytes({
    required String id,
    required Uint8List bytes,
    Duration? duration,
  }) {
    if (bytes.isEmpty) {
      throw ArgumentError.value(bytes, 'bytes', 'Must not be empty.');
    }
    return AudioTrack(id: id, bytes: bytes, duration: duration);
  }

  /// Creates a track backed by a local path or provider URL.
  factory AudioTrack.fromLocation({
    required String id,
    required String location,
    Duration? duration,
  }) {
    if (location.trim().isEmpty) {
      throw ArgumentError.value(location, 'location', 'Must not be empty.');
    }
    return AudioTrack(id: id, location: location, duration: duration);
  }

  final String id;
  final Uint8List? bytes;
  final String? location;
  final Duration? duration;
}

/// A playback handle returned once playback has actually started.
final class AudioPlayback {
  const AudioPlayback({
    required this.startedAt,
    required this.completed,
    this.progress = const Stream<AudioPlaybackProgress>.empty(),
  });

  final DateTime startedAt;
  final Future<void> completed;
  final Stream<AudioPlaybackProgress> progress;
}

/// The current player position and its known total duration.
final class AudioPlaybackProgress {
  const AudioPlaybackProgress({required this.position, this.duration});

  final Duration position;
  final Duration? duration;
}

enum NarrationOutcomeKind { spoken, silent, failed }

final class NarrationOutcome {
  const NarrationOutcome._({
    required this.kind,
    required this.observedAt,
    this.text,
    this.reason,
    this.error,
    this.playbackStartedAt,
  });

  factory NarrationOutcome.spoken({
    required DateTime observedAt,
    required DateTime playbackStartedAt,
    required String text,
  }) {
    return NarrationOutcome._(
      kind: NarrationOutcomeKind.spoken,
      observedAt: observedAt,
      playbackStartedAt: playbackStartedAt,
      text: text,
    );
  }

  factory NarrationOutcome.silent({
    required DateTime observedAt,
    required String reason,
  }) {
    return NarrationOutcome._(
      kind: NarrationOutcomeKind.silent,
      observedAt: observedAt,
      reason: reason,
    );
  }

  factory NarrationOutcome.failed({
    required DateTime observedAt,
    required Object error,
  }) {
    return NarrationOutcome._(
      kind: NarrationOutcomeKind.failed,
      observedAt: observedAt,
      error: error,
    );
  }

  final NarrationOutcomeKind kind;
  final DateTime observedAt;
  final String? text;
  final String? reason;
  final Object? error;
  final DateTime? playbackStartedAt;
}

sealed class NarrationEngineEvent {
  const NarrationEngineEvent({
    required this.captures,
    required this.observedAt,
  });

  final List<CapturedImage> captures;
  final DateTime observedAt;
}

final class NarrationStarted extends NarrationEngineEvent {
  const NarrationStarted({
    required super.captures,
    required super.observedAt,
    required this.playbackStartedAt,
    required this.text,
  });

  final DateTime playbackStartedAt;
  final String text;
}

final class NarrationProgress extends NarrationEngineEvent {
  const NarrationProgress({
    required super.captures,
    required super.observedAt,
    required this.text,
    required this.position,
    required this.duration,
  });

  final String text;
  final Duration position;
  final Duration? duration;
}

final class NarrationFinished extends NarrationEngineEvent {
  const NarrationFinished({
    required super.captures,
    required super.observedAt,
    required this.playbackStartedAt,
    required this.playbackFinishedAt,
    required this.text,
  });

  final DateTime playbackStartedAt;
  final DateTime playbackFinishedAt;
  final String text;
}

final class NarrationSkipped extends NarrationEngineEvent {
  const NarrationSkipped({
    required super.captures,
    required super.observedAt,
    required this.reason,
  });

  final String reason;
}

final class NarrationFailed extends NarrationEngineEvent {
  const NarrationFailed({
    required super.captures,
    required super.observedAt,
    required this.error,
  });

  final Object error;
}
