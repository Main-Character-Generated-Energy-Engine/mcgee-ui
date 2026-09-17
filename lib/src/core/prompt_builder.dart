import 'models.dart';

abstract interface class NarrationPromptBuilder {
  String build({
    required SceneObservation observation,
    required NarrativeMemorySnapshot memory,
  });
}

/// Supplies scene and story data. Writing rules live in writer_instructions.dart.
final class DocumentaryPromptBuilder implements NarrationPromptBuilder {
  const DocumentaryPromptBuilder();

  @override
  String build({
    required SceneObservation observation,
    required NarrativeMemorySnapshot memory,
  }) => _buildContext(observation, memory);
}

/// The live writer receives the same context as the non-streaming writer.
final class ContinuousDocumentaryPromptBuilder
    implements NarrationPromptBuilder {
  const ContinuousDocumentaryPromptBuilder();

  @override
  String build({
    required SceneObservation observation,
    required NarrativeMemorySnapshot memory,
  }) => _buildContext(observation, memory);
}

String _buildContext(
  SceneObservation observation,
  NarrativeMemorySnapshot memory,
) {
  final details = observation.details.entries
      .map((entry) => '- ${entry.key}: ${entry.value}')
      .join('\n');
  final canon = memory.canon.entries
      .map((entry) => '- ${entry.key}: ${entry.value}')
      .join('\n');
  final recentLines = memory.recentNarrations
      .map((entry) => '- ${entry.text}')
      .join('\n');
  final storySummary = memory.canon['story_summary'] ?? memory.storySummary;
  final lastLine = memory.recentNarrations.isEmpty
      ? '(none)'
      : memory.recentNarrations.last.text;
  return '''Current observation:
${observation.description}

Visible scene details:
${details.isEmpty ? '(none)' : details}

Established canon:
${canon.isEmpty ? '(none)' : canon}

Story so far — older spoken beats:
${storySummary.isEmpty ? '(none)' : storySummary}

Current activity:
${memory.canon['current_activity'] ?? '(none)'}

Open story thread:
${memory.canon['open_thread'] ?? '(none)'}

Immediately preceding narration (oldest to newest):
${recentLines.isEmpty ? '(none)' : recentLines}

Last spoken line — continue this beat:
$lastLine''';
}
