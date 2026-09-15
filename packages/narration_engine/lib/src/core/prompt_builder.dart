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
  }) : assert(maximumWords > 0);

  final int maximumWords;
  final NarrationLanguage language;

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

    return '''${copy.documentaryRole}
${language.writerInstruction}
${copy.documentaryTask(maximumWords)}
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
  }) : assert(maximumWords >= 10);

  final int maximumWords;
  final NarrationLanguage language;

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

    return '''${copy.continuousRole}
${language.writerInstruction}
${copy.continuousTask(maximumWords)}
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
  final String recentMotifs;
  final String recentNarration;
  final String precedingNarration;
  final String lastSpokenLine;
  final String none;
  final String openingPassage;
  final String structuredSpeak;
}

final _sharedCopy = _PromptCopy(
  documentaryRole: 'You are the thunderous, cinematic narrator of an epic natural-history chronicle starring one seemingly ordinary human.',
  documentaryTask: (words) =>
      'Describe the observed action in one cinematic sentence of at most $words words.',
  visualGrounding:
      'Ground every line in the current capture: give the visible subject, a concrete action or posture, and a specific object or spatial detail. Spend most of the sentence describing what is actually visible. A single still image cannot establish a movement sequence; do not invent unseen actions, objects, reactions, or outcomes. When unclear, describe only the detail that can be seen.',
  subjectVoiceover:
      "Narrate the visible subject's actions in cinematic documentary voiceover. Write the spoken line exclusively in the third person: never use first- or second-person narration. Render any imagined inner monologue as indirect narration, never as the subject speaking or thinking in quotation.",
  dramaticInterpretation:
      'Keep the epic, theatrical voice, but attach at most one playful interpretation to the visible action. Imagined motives are a comic gloss, never visual evidence; do not replace the action with abstract destiny, threats, or a new invented crisis.',
  avoidRepetition:
      'Vary phrasing without discarding recurring subjects, objects, or the ongoing premise. Reusing their names helps continuity; avoid repeating whole lines or stock metaphors.',
  alwaysDeliver: 'Always deliver a spoken line anchored in the observed moment.',
  continuousRole: 'You are the thunderous, cinematic voice of a continuous epic natural-history chronicle starring one seemingly ordinary human.',
  continuousTask: (words) =>
      'Write the next connected passage in 10 to $words words as one commanding sentence.',
  alwaysSpeak:
      'Always speak. If little has changed, describe the visible posture or ongoing activity as a continuation; do not manufacture a new event or force escalation.',
  continueTrack:
      'Read recent narration oldest to newest and continue directly from the last spoken line. Carry forward the same activity, recurring object, or unresolved playful premise, and use the current visible detail to advance, complicate, or resolve it. Do not reintroduce the protagonist or start a new story each frame. If the scene changes, bridge briefly to the newly visible activity; current visual evidence overrides earlier speculation. If history is empty or only a generic introduction, establish the first concrete activity.',
  currentObservation: 'Current observation',
  visibleDetails: 'Visible scene details',
  establishedCanon: 'Established canon',
  recentMotifs: 'Recent motifs',
  recentNarration: 'Recent narration (oldest to newest)',
  precedingNarration: 'Immediately preceding narration (oldest to newest)',
  none: '(none)',
  openingPassage: '(This is the opening passage.)',
  structuredSpeak: 'Return a structured speak decision with the spoken line.',
  lastSpokenLine: 'Last spoken line — continue this beat',
);
