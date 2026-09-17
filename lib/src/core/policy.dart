import 'models.dart';

enum SilenceReason {
  busy,
  tooSoon,
  rollingLimit,
  staleObservation,
  narratorChoseSilence,
  emptyNarration,
}

extension SilenceReasonMessage on SilenceReason {
  String get message => switch (this) {
    SilenceReason.busy => 'The engine is already handling another moment.',
    SilenceReason.tooSoon => 'The previous narration is too recent.',
    SilenceReason.rollingLimit =>
      'The rolling narration limit has been reached.',
    SilenceReason.staleObservation =>
      'The observed moment is no longer timely enough to narrate.',
    SilenceReason.narratorChoseSilence =>
      'The narrator decided silence was better.',
    SilenceReason.emptyNarration => 'The narrator returned no usable text.',
  };
}

/// Scheduling and freshness limits; prose quality belongs to the writer prompt.
final class NarrationPolicy {
  const NarrationPolicy({
    this.minimumGap = const Duration(seconds: 20),
    this.maximumObservationAge = const Duration(seconds: 30),
    this.rollingWindow = const Duration(minutes: 3),
    this.maxNarrationsPerWindow = 4,
  }) : assert(maxNarrationsPerWindow > 0);

  final Duration minimumGap;
  final Duration? maximumObservationAge;
  final Duration rollingWindow;
  final int maxNarrationsPerWindow;

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
}
