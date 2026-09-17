import 'models.dart';

/// Say the name once, then leave three spoken beats before using it again.
const nameCooldownBeats = 3;

bool recentlyNamed(NarrativeMemorySnapshot memory, String name) => memory
    .recentNarrations
    .reversed
    .take(nameCooldownBeats)
    .any((entry) => containsCharacterName(entry.text, name));

bool containsCharacterName(String text, String name) => RegExp(
  '(^|[^\\p{L}\\p{N}_])${RegExp.escape(name)}(?=\$|[^\\p{L}\\p{N}_])',
  caseSensitive: false,
  unicode: true,
).hasMatch(text);

String nameCadenceInstruction(NarrativeMemorySnapshot memory, String name) {
  return recentlyNamed(memory, name)
      ? 'Omit the character name in this passage: it appeared in the last '
            'three spoken beats. Let the ongoing task, object, or snag '
            'carry this sentence.'
      : 'Use the supplied character name exactly once in this passage. '
            'Work it naturally into the ongoing action; do not reintroduce '
            'the character or restart the story.';
}

bool violatesNameCadence(
  String text,
  NarrativeMemorySnapshot memory,
  String name,
) {
  if (name.isEmpty) return false;
  final usesName = containsCharacterName(text, name);
  return recentlyNamed(memory, name) ? usesName : !usesName;
}
