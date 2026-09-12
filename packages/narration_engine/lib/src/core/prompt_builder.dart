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
