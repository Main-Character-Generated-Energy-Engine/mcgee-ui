import 'package:narration_engine/narration_engine.dart';
import 'package:narration_engine/src/core/name_cadence.dart';
import 'package:test/test.dart';

void main() {
  NarrativeMemorySnapshot history(List<String> lines) => NarrativeMemorySnapshot(
    recentNarrations: [
      for (final line in lines)
        NarrationMemoryEntry(text: line, observedAt: DateTime.utc(2026)),
    ],
  );

  test('requires the name again after three unnamed beats', () {
    final lines = [
      'Ari needs an excuse.',
      'The plan fails.',
      'A delay helps.',
    ];
    expect(violatesNameCadence('The excuse suits Ari.', history(lines), 'Ari'), isTrue);
    expect(violatesNameCadence('The excuse works.', history(lines), 'Ari'), isFalse);
    lines.add('The delay backfires.');
    expect(violatesNameCadence('The excuse suits Ari.', history(lines), 'Ari'), isFalse);
    expect(violatesNameCadence('Ari has another idea.', history(lines), 'Ari'), isFalse);
    expect(violatesNameCadence('The excuse works.', history(lines), 'Ari'), isTrue);
    expect(nameCadenceInstruction(history(lines), 'Ari'), contains('name exactly once'));
    lines.add('Ari has another idea.');
    expect(violatesNameCadence('Ari needs time.', history(lines), 'Ari'), isTrue);
  });

  test('matches names as words including accents and possessives', () {
    expect(containsCharacterName('Paris is quiet.', 'Ari'), isFalse);
    expect(containsCharacterName('Ari’s excuse fails.', 'Ari'), isTrue);
    expect(containsCharacterName('The plan suits Éloïse.', 'Éloïse'), isTrue);
  });
}
