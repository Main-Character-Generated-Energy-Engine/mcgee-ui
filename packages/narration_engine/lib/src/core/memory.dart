import 'models.dart';

/// Small, bounded story memory. It intentionally is not a transcript store.
final class NarrativeMemory {
  NarrativeMemory({
    this.maxObservations = 8,
    this.maxNarrations = 10,
    this.maxCanonEntries = 12,
  }) : assert(maxObservations > 0),
       assert(maxNarrations > 0),
       assert(maxCanonEntries > 0);

  final int maxObservations;
  final int maxNarrations;
  final int maxCanonEntries;

  final List<SceneObservation> _observations = <SceneObservation>[];
  final List<NarrationMemoryEntry> _narrations = <NarrationMemoryEntry>[];
  final Map<String, String> _canon = <String, String>{};

  NarrativeMemorySnapshot get snapshot => NarrativeMemorySnapshot(
    recentObservations: List<SceneObservation>.unmodifiable(_observations),
    recentNarrations: List<NarrationMemoryEntry>.unmodifiable(_narrations),
    canon: Map<String, String>.unmodifiable(_canon),
  );

  void recordObservation(SceneObservation observation) {
    _observations.add(observation);
    _trimStart(_observations, maxObservations);
  }

  void recordNarration({
    required String text,
    required DateTime observedAt,
    List<String> motifs = const <String>[],
    Map<String, String> canonUpdates = const <String, String>{},
  }) {
    _narrations.add(
      NarrationMemoryEntry(
        text: text,
        observedAt: observedAt,
        motifs: List<String>.unmodifiable(motifs),
      ),
    );
    _trimStart(_narrations, maxNarrations);

    for (final MapEntry<String, String> update in canonUpdates.entries) {
      _canon.remove(update.key);
      _canon[update.key] = update.value;
    }
    while (_canon.length > maxCanonEntries) {
      _canon.remove(_canon.keys.first);
    }
  }

  void clear() {
    _observations.clear();
    _narrations.clear();
    _canon.clear();
  }

  static void _trimStart<T>(List<T> values, int maximum) {
    if (values.length > maximum) {
      values.removeRange(0, values.length - maximum);
    }
  }
}
