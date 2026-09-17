import 'models.dart';

/// Small, bounded story memory. It intentionally is not a transcript store.
final class NarrativeMemory {
  NarrativeMemory({
    this.maxObservations = 8,
    this.maxNarrations = 10,
    this.maxCanonEntries = 12,
    this.maxSummaryCharacters = 1200,
  }) : assert(maxObservations > 0),
       assert(maxNarrations > 0),
       assert(maxCanonEntries > 0),
       assert(maxSummaryCharacters > 0);

  factory NarrativeMemory.fromSnapshot(
    NarrativeMemorySnapshot snapshot, {
    int maxObservations = 8,
    int maxNarrations = 10,
    int maxCanonEntries = 12,
    int maxSummaryCharacters = 1200,
  }) {
    final memory = NarrativeMemory(
      maxObservations: maxObservations,
      maxNarrations: maxNarrations,
      maxCanonEntries: maxCanonEntries,
      maxSummaryCharacters: maxSummaryCharacters,
    );
    for (final observation in snapshot.recentObservations) {
      memory.recordObservation(observation);
    }
    if (snapshot.storySummary.trim().isNotEmpty) {
      memory._appendSummaryBeat(snapshot.storySummary);
    }
    for (final narration in snapshot.recentNarrations) {
      memory.recordNarration(
        text: narration.text,
        observedAt: narration.observedAt,
        motifs: narration.motifs,
      );
    }
    for (final entry in snapshot.canon.entries) {
      memory._canon[entry.key] = entry.value;
      while (memory._canon.length > maxCanonEntries) {
        memory._canon.remove(memory._canon.keys.first);
      }
    }
    return memory;
  }

  final int maxObservations;
  final int maxNarrations;
  final int maxCanonEntries;
  final int maxSummaryCharacters;

  final List<SceneObservation> _observations = <SceneObservation>[];
  final List<NarrationMemoryEntry> _narrations = <NarrationMemoryEntry>[];
  final Map<String, String> _canon = <String, String>{};
  final List<String> _storySummaryBeats = <String>[];

  NarrativeMemorySnapshot get snapshot => NarrativeMemorySnapshot(
    recentObservations: List<SceneObservation>.unmodifiable(_observations),
    recentNarrations: List<NarrationMemoryEntry>.unmodifiable(_narrations),
    canon: Map<String, String>.unmodifiable(_canon),
    storySummary: _storySummaryBeats.join(' '),
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
    while (_narrations.length > maxNarrations) {
      _appendSummaryBeat(_narrations.removeAt(0).text);
    }

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
    _storySummaryBeats.clear();
  }

  void _appendSummaryBeat(String text) {
    _storySummaryBeats.add(text.trim());
    while (_storySummaryBeats.length > 1 &&
        _storySummaryBeats.join(' ').length > maxSummaryCharacters) {
      _storySummaryBeats.removeAt(0);
    }
    if (_storySummaryBeats.length == 1 &&
        _storySummaryBeats[0].length > maxSummaryCharacters) {
      final only = _storySummaryBeats[0];
      _storySummaryBeats[0] = only.substring(
        only.length - maxSummaryCharacters,
      );
    }
  }

  static void _trimStart<T>(List<T> values, int maximum) {
    if (values.length > maximum) {
      values.removeRange(0, values.length - maximum);
    }
  }
}
