import 'models.dart';
import 'narration_language.dart';

abstract interface class NarrationPromptBuilder {
  String build({
    required SceneObservation observation,
    required NarrativeMemorySnapshot memory,
  });
}

/// Default prompt for visually grounded, connected documentary narration.
final class DocumentaryPromptBuilder implements NarrationPromptBuilder {
  const DocumentaryPromptBuilder({
    this.maximumWords = 30,
    this.language = NarrationLanguage.english,
    this.characterName,
  }) : assert(maximumWords > 0);

  final int maximumWords;
  final NarrationLanguage language;
  final String? characterName;

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

    final copy = _sharedCopy;
    final namedCharacter = _namedCharacterInstruction(characterName, memory);
    final storySummary = memory.canon['story_summary'] ?? memory.storySummary;
    final currentActivity = memory.canon['current_activity'];
    final openThread = memory.canon['open_thread'];

    return '''${copy.documentaryRole}
${language.writerInstruction}
${namedCharacter.isEmpty ? '' : '$namedCharacter\n'}${copy.documentaryTask(maximumWords)}
${copy.visualGrounding}
${copy.subjectVoiceover}
${copy.dramaticInterpretation}
${copy.continueTrack}
${copy.avoidRepetition}
${copy.alwaysDeliver}

${copy.currentObservation}:
${observation.description}

${copy.visibleDetails}:
${details.isEmpty ? copy.none : details}

${copy.establishedCanon}:
${canon.isEmpty ? copy.none : canon}

${copy.storySoFar}:
${storySummary.isEmpty ? copy.none : storySummary}

Current activity:
${(currentActivity?.isNotEmpty ?? false) ? currentActivity : copy.none}

Open story thread — preserve until advanced or resolved:
${(openThread?.isNotEmpty ?? false) ? openThread : copy.none}

${copy.recentMotifs}:
${recentMotifs.isEmpty ? copy.none : recentMotifs}

${copy.recentNarration}:
${recentLines.isEmpty ? copy.none : recentLines}

${copy.lastSpokenLine}:
${memory.recentNarrations.isEmpty ? copy.openingPassage : memory.recentNarrations.last.text}

${copy.structuredSpeak}''';
  }
}

/// Prompt for a live narration stream whose passages should connect naturally.
final class ContinuousDocumentaryPromptBuilder
    implements NarrationPromptBuilder {
  const ContinuousDocumentaryPromptBuilder({
    this.maximumWords = 20,
    this.language = NarrationLanguage.english,
    this.characterName,
  }) : assert(maximumWords >= 10);

  final int maximumWords;
  final NarrationLanguage language;
  final String? characterName;

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

    final copy = _sharedCopy;
    final namedCharacter = _namedCharacterInstruction(characterName, memory);
    final storySummary = memory.canon['story_summary'] ?? memory.storySummary;
    final currentActivity = memory.canon['current_activity'];
    final openThread = memory.canon['open_thread'];

    return '''${copy.continuousRole}
${language.writerInstruction}
${namedCharacter.isEmpty ? '' : '$namedCharacter\n'}${copy.continuousTask(maximumWords)}
${copy.visualGrounding}
${copy.alwaysSpeak}
${copy.continueTrack}
${copy.avoidRepetition}
${copy.subjectVoiceover}
${copy.dramaticInterpretation}

${copy.currentObservation}:
${observation.description}

${copy.visibleDetails}:
${details.isEmpty ? copy.none : details}

${copy.establishedCanon}:
${canon.isEmpty ? copy.none : canon}

${copy.storySoFar}:
${storySummary.isEmpty ? copy.none : storySummary}

Current activity:
${(currentActivity?.isNotEmpty ?? false) ? currentActivity : copy.none}

Open story thread — preserve until advanced or resolved:
${(openThread?.isNotEmpty ?? false) ? openThread : copy.none}

${copy.precedingNarration}:
${recentLines.isEmpty ? copy.openingPassage : recentLines}

${copy.lastSpokenLine}:
${memory.recentNarrations.isEmpty ? copy.openingPassage : memory.recentNarrations.last.text}

${copy.structuredSpeak}''';
  }
}

typedef _WordLimitCopy = String Function(int maximumWords);

final class _PromptCopy {
  const _PromptCopy({
    required this.documentaryRole,
    required this.documentaryTask,
    required this.visualGrounding,
    required this.subjectVoiceover,
    required this.dramaticInterpretation,
    required this.avoidRepetition,
    required this.alwaysDeliver,
    required this.continuousRole,
    required this.continuousTask,
    required this.alwaysSpeak,
    required this.continueTrack,
    required this.currentObservation,
    required this.visibleDetails,
    required this.establishedCanon,
    required this.storySoFar,
    required this.recentMotifs,
    required this.recentNarration,
    required this.precedingNarration,
    required this.lastSpokenLine,
    required this.none,
    required this.openingPassage,
    required this.structuredSpeak,
  });

  final String documentaryRole;
  final _WordLimitCopy documentaryTask;
  final String visualGrounding;
  final String subjectVoiceover;
  final String dramaticInterpretation;
  final String avoidRepetition;
  final String alwaysDeliver;
  final String continuousRole;
  final _WordLimitCopy continuousTask;
  final String alwaysSpeak;
  final String continueTrack;
  final String currentObservation;
  final String visibleDetails;
  final String establishedCanon;
  final String storySoFar;
  final String recentMotifs;
  final String recentNarration;
  final String precedingNarration;
  final String lastSpokenLine;
  final String none;
  final String openingPassage;
  final String structuredSpeak;
}

final _sharedCopy = _PromptCopy(
  documentaryRole: 'You are the assured, observant, dryly amused narrator of a cinematic natural-history film starring one seemingly ordinary human.',
  documentaryTask: (words) =>
      'Describe the observed action in one confident, complete cinematic sentence of at most $words words.',
  visualGrounding:
      'Ground every line in the current capture: give the visible subject, a concrete action or posture, and a specific object or spatial detail. Spend most of the sentence describing what is actually visible. A single still image cannot establish a movement sequence; do not invent unseen actions, objects, reactions, or outcomes. When unclear, describe only the detail that can be seen.',
  subjectVoiceover:
      "Narrate the visible subject's actions in cinematic documentary voiceover. Write the spoken line exclusively in the third person: never use first- or second-person narration. Render any imagined inner monologue as indirect narration, never as the subject speaking or thinking in quotation.",
  dramaticInterpretation:
      'Use precise wording and at most one disproportionate, playful judgment. Imagined motives are comic framing, never visual evidence; do not replace the action with abstract destiny, threats, or a new invented crisis.',
  avoidRepetition:
      'Vary phrasing without discarding recurring subjects, objects, or the ongoing premise. Reusing their names helps continuity; avoid repeating whole lines or stock metaphors.',
  alwaysDeliver: 'Always deliver a spoken line anchored in the observed moment.',
  continuousRole: 'You are the assured, observant, dryly amused voice of one continuous cinematic natural-history film starring one seemingly ordinary human.',
  continuousTask: (words) =>
      'Write the next connected passage in 10 to $words words as one confident, complete sentence.',
  alwaysSpeak:
      'Always speak. If little has changed, describe the visible posture or ongoing activity as a continuation; do not manufacture a new event or force escalation.',
  continueTrack:
      'Read recent narration oldest to newest and continue directly from the last spoken line. Carry forward the same activity, recurring object, or unresolved playful premise, and use the current visible detail to advance, complicate, or resolve it. Do not reintroduce the protagonist or start a new story each frame. If the scene changes, bridge briefly to the newly visible activity; current visual evidence overrides earlier speculation. If history is empty or only a generic introduction, establish the first concrete activity.',
  currentObservation: 'Current observation',
  visibleDetails: 'Visible scene details',
  establishedCanon: 'Established canon',
  storySoFar: 'Story so far — older spoken beats',
  recentMotifs: 'Recent motifs',
  recentNarration: 'Recent narration (oldest to newest)',
  precedingNarration: 'Immediately preceding narration (oldest to newest)',
  none: '(none)',
  openingPassage: '(This is the opening passage.)',
  structuredSpeak: 'Return a structured speak decision with the spoken line.',
  lastSpokenLine: 'Last spoken line — continue this beat',
);

String _namedCharacterInstruction(
  String? name,
  NarrativeMemorySnapshot memory,
) {
  final normalized = name?.trim() ?? '';
  if (normalized.isEmpty) return '';
  final recentNameUse = memory.recentNarrations
      .reversed
      .take(2)
      .any((entry) => entry.text.toLowerCase().contains(normalized.toLowerCase()));
  final cadence = recentNameUse
      ? 'Use the name or a pronoun according to natural cinematic rhythm; do '
            'not begin every line with the name.'
      : 'Use that exact name naturally in this spoken passage.';
  return 'The protagonist is named "$normalized". $cadence If the image does '
      'not clearly show a person, the name is only a narrative anchor, not '
      'evidence that the person is visible. Never use a generic label such as '
      'the subject or protagonist in the spoken line.';
}
