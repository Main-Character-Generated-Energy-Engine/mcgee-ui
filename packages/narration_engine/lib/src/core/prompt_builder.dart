import 'models.dart';

abstract interface class NarrationPromptBuilder {
  String build({
    required SceneObservation observation,
    required NarrativeMemorySnapshot memory,
  });
}

/// Compact default prompt that gives a model both taste and permission to stop.
final class DocumentaryPromptBuilder implements NarrationPromptBuilder {
  const DocumentaryPromptBuilder({this.maximumWords = 30})
    : assert(maximumWords > 0);

  final int maximumWords;

  @override
  String build({
    required SceneObservation observation,
    required NarrativeMemorySnapshot memory,
  }) {
    final recentLines = memory.recentNarrations
        .map((entry) => '- ${entry.text}')
        .join('\n');
    final recentMotifs = memory.recentNarrations
        .expand((entry) => entry.motifs)
        .toSet()
        .join(', ');
    final canon = memory.canon.entries
        .map((entry) => '- ${entry.key}: ${entry.value}')
        .join('\n');
    final details = observation.details.entries
        .map((entry) => '- ${entry.key}: ${entry.value}')
        .join('\n');

    return '''You are the restrained narrator of a nature documentary about one ordinary human protagonist.
Transform the literal observation into one dry, dramatic line of at most $maximumWords words.
Prefer specific behavior over generic grandeur. Preserve established fictional continuity, but do not force it.
Do not infer sensitive traits or facts that are not visible.
Avoid wording, metaphors, and motifs used recently.
Silence is a first-class editorial choice: choose it when the scene is unchanged, weak, repetitive, or funnier without comment.

Current observation:
${observation.description}

Visible scene details:
${details.isEmpty ? '(none)' : details}

Established canon:
${canon.isEmpty ? '(none)' : canon}

Recent motifs:
${recentMotifs.isEmpty ? '(none)' : recentMotifs}

Recent narration:
${recentLines.isEmpty ? '(none)' : recentLines}

Return a structured speak-or-silence decision.''';
  }
}

/// Prompt for a live narration stream whose passages should connect naturally.
final class ContinuousDocumentaryPromptBuilder
    implements NarrationPromptBuilder {
  const ContinuousDocumentaryPromptBuilder({this.maximumWords = 20})
    : assert(maximumWords >= 10);

  final int maximumWords;

  @override
  String build({
    required SceneObservation observation,
    required NarrativeMemorySnapshot memory,
  }) {
    final recentLines = memory.recentNarrations
        .map((entry) => '- ${entry.text}')
        .join('\n');
    final canon = memory.canon.entries
        .map((entry) => '- ${entry.key}: ${entry.value}')
        .join('\n');
    final details = observation.details.entries
        .map((entry) => '- ${entry.key}: ${entry.value}')
        .join('\n');

    return '''You are providing continuous live nature-documentary narration about one ordinary human protagonist.
Write the next connected passage in 10 to $maximumWords words as one concise sentence.
Always speak. Even when little has changed, advance the commentary through precise visible detail, gentle anticipation, or continuity with the previous passage.
Treat recent narration as the preceding part of one flowing track: continue from it without repeating its wording or restarting the premise.
Stay grounded in visible behavior. Do not infer sensitive traits or facts that are not visible.

Current observation:
${observation.description}

Visible scene details:
${details.isEmpty ? '(none)' : details}

Established canon:
${canon.isEmpty ? '(none)' : canon}

Immediately preceding narration:
${recentLines.isEmpty ? '(This is the opening passage.)' : recentLines}

Return a structured speak decision with the next passage.''';
  }
}
