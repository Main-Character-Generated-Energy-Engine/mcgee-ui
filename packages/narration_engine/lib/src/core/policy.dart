import 'models.dart';

enum SilenceReason {
  busy,
  tooSoon,
  rollingLimit,
  staleObservation,
  lowSalience,
  unchangedScene,
  narratorChoseSilence,
  emptyNarration,
  narrationTooLong,
  repeatedNarration,
}

extension SilenceReasonMessage on SilenceReason {
  String get message => switch (this) {
    SilenceReason.busy => 'The engine is already handling another moment.',
    SilenceReason.tooSoon => 'The previous narration is too recent.',
    SilenceReason.rollingLimit =>
      'The rolling narration limit has been reached.',
    SilenceReason.staleObservation =>
      'The observed moment is no longer timely enough to narrate.',
    SilenceReason.lowSalience => 'The moment is not significant enough.',
    SilenceReason.unchangedScene => 'The scene has not meaningfully changed.',
    SilenceReason.narratorChoseSilence =>
      'The narrator decided silence was better.',
    SilenceReason.emptyNarration => 'The narrator returned no usable text.',
    SilenceReason.narrationTooLong =>
      'The proposed narration exceeded the word limit.',
    SilenceReason.repeatedNarration =>
      'The proposed narration was too repetitive.',
  };
}

/// Deterministic editorial gates around the model's own decision to speak.
final class NarrationPolicy {
  const NarrationPolicy({
    this.minimumGap = const Duration(seconds: 20),
    this.maximumObservationAge = const Duration(seconds: 30),
    this.rollingWindow = const Duration(minutes: 3),
    this.maxNarrationsPerWindow = 4,
    this.minimumSalience = 0.25,
    this.sceneLookback = 2,
    this.maximumWords = 30,
    this.duplicateThreshold = 0.72,
  }) : assert(maxNarrationsPerWindow > 0),
       assert(minimumSalience >= 0 && minimumSalience <= 1),
       assert(sceneLookback >= 0),
       assert(maximumWords > 0),
       assert(duplicateThreshold >= 0 && duplicateThreshold <= 1);

  final Duration minimumGap;

  /// Set to null for retrospective rendering of historical captures.
  final Duration? maximumObservationAge;
  final Duration rollingWindow;
  final int maxNarrationsPerWindow;
  final double minimumSalience;
  final int sceneLookback;
  final int maximumWords;
  final double duplicateThreshold;

  SilenceReason? checkTiming(
    DateTime observedAt,
    NarrativeMemorySnapshot memory,
  ) {
    assert(!minimumGap.isNegative);
    assert(!rollingWindow.isNegative);
    final narrations = memory.recentNarrations;
    if (narrations.isNotEmpty) {
      final elapsed = observedAt.difference(narrations.last.observedAt);
      if (elapsed.isNegative || elapsed < minimumGap) {
        return SilenceReason.tooSoon;
      }
    }

    final windowStart = observedAt.subtract(rollingWindow);
    final inWindow = narrations.where(
      (entry) =>
          !entry.observedAt.isBefore(windowStart) &&
          !entry.observedAt.isAfter(observedAt),
    );
    if (inWindow.length >= maxNarrationsPerWindow) {
      return SilenceReason.rollingLimit;
    }
    return null;
  }

  SilenceReason? checkStaleness(DateTime observedAt, DateTime now) {
    final maximumAge = maximumObservationAge;
    if (maximumAge == null) return null;
    assert(!maximumAge.isNegative);
    final age = now.difference(observedAt);
    if (!age.isNegative && age > maximumAge) {
      return SilenceReason.staleObservation;
    }
    return null;
  }

  SilenceReason? checkObservation(
    SceneObservation observation,
    NarrativeMemorySnapshot memory,
  ) {
    if (observation.salience < minimumSalience) {
      return SilenceReason.lowSalience;
    }
    if (sceneLookback == 0 || observation.fingerprint.trim().isEmpty) {
      return null;
    }
    final observations = memory.recentObservations;
    final start = observations.length > sceneLookback
        ? observations.length - sceneLookback
        : 0;
    for (var index = start; index < observations.length; index += 1) {
      if (observations[index].fingerprint == observation.fingerprint) {
        return SilenceReason.unchangedScene;
      }
    }
    return null;
  }

  SilenceReason? checkDraft(String text, NarrativeMemorySnapshot memory) {
    if (text.trim().isEmpty) {
      return SilenceReason.emptyNarration;
    }
    if (_wordCount(text) > maximumWords) {
      return SilenceReason.narrationTooLong;
    }
    final candidate = _tokens(text);
    for (final entry in memory.recentNarrations) {
      if (_jaccard(candidate, _tokens(entry.text)) >= duplicateThreshold) {
        return SilenceReason.repeatedNarration;
      }
    }
    return null;
  }

  static Set<String> _tokens(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toSet();
  }

  static int _wordCount(String text) {
    return text
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .length;
  }

  static double _jaccard(Set<String> left, Set<String> right) {
    if (left.isEmpty && right.isEmpty) {
      return 1;
    }
    final intersection = left.intersection(right).length;
    final union = left.union(right).length;
    return intersection / union;
  }
}
