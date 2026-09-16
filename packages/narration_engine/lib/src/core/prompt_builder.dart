import 'models.dart';
import 'name_cadence.dart';
import 'narration_language.dart';
import 'writer_instructions.dart';

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
    this.narratorInstructions,
  }) : assert(maximumWords > 0);

  final int maximumWords;
  final NarrationLanguage language;
  final String? characterName;

  /// Optional host-selected genre and tense, evaluated for each passage.
  final String Function()? narratorInstructions;

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
    final mode = narratorInstructions?.call();
    final namedCharacter = _namedCharacterInstruction(characterName, memory, profiled: mode != null);
    final storySummary = memory.canon['story_summary'] ?? memory.storySummary;
    final currentActivity = memory.canon['current_activity'];
    final openThread = memory.canon['open_thread'];

    return '''${mode ?? copy.documentaryRole}
${language.writerInstruction}
${namedCharacter.isEmpty ? '' : '$namedCharacter\n'}${copy.documentaryTask(maximumWords)}
${copy.visualGrounding}
${mode == null ? copy.subjectVoiceover : ''}
${mode == null ? copy.dramaticInterpretation : _profiledDramaticInterpretation}
${mode == null ? copy.continueTrack : _profiledContinueTrack}
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
    this.narratorInstructions,
  }) : assert(maximumWords >= 10);

  final int maximumWords;
  final NarrationLanguage language;
  final String? characterName;

  /// Optional host-selected genre and tense, evaluated for each passage.
  final String Function()? narratorInstructions;

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
    final mode = narratorInstructions?.call();
    final namedCharacter = _namedCharacterInstruction(characterName, memory, profiled: mode != null);
    final storySummary = memory.canon['story_summary'] ?? memory.storySummary;
    final currentActivity = memory.canon['current_activity'];
    final openThread = memory.canon['open_thread'];

    return '''${mode ?? copy.continuousRole}
${language.writerInstruction}
${namedCharacter.isEmpty ? '' : '$namedCharacter\n'}${mode != null && memory.hasOnlyOpening ? sceneSettingPassageInstruction : copy.continuousTask(maximumWords)}
${copy.visualGrounding}
${copy.alwaysSpeak}
${mode == null ? copy.continueTrack : _profiledContinueTrack}
${copy.avoidRepetition}
${mode == null ? copy.subjectVoiceover : ''}
${mode == null ? copy.dramaticInterpretation : _profiledDramaticInterpretation}

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
  documentaryRole: 'You are the observant, dryly amused narrator inventing one continuous fictional story starring one ordinary human.',
  documentaryTask: (words) =>
      'Advance the ongoing fictional story in one complete sentence of at most $words words.',
  visualGrounding:
      'Ground every line in the current capture with one discernible action, posture, object, or spatial detail, and make it serve the fictional story. The visual anchor need not come first or occupy most of the sentence. Do not claim to see absent objects, unseen movement, or unobserved physical outcomes.',
  subjectVoiceover:
      "Narrate the visible subject's actions in cinematic documentary voiceover. Write the spoken line exclusively in the third person: never use first- or second-person narration. Render any imagined inner monologue as indirect narration, never as the subject speaking or thinking in quotation.",
  dramaticInterpretation:
      'Invent and sustain a small fictional goal, its snag, and developments caused by earlier beats. Imagined motives and consequences are story canon, never verified personal facts. Keep them consistent and avoid grandiose abstractions or unrelated punchlines.',
  avoidRepetition:
      'Vary phrasing without discarding recurring subjects, objects, or the ongoing premise. Reusing their names helps continuity; avoid repeating whole lines or stock metaphors.',
  alwaysDeliver: 'Always deliver a spoken line anchored in the observed moment.',
  continuousRole: 'You are the observant, dryly amused voice of one continuous fictional film starring one ordinary human.',
  continuousTask: (words) =>
      'Write the next connected passage in 10 to $words words as one confident, complete sentence.',
  alwaysSpeak:
      'Always speak. If little changes visually, develop the same fictional dilemma through a new interpretation, hesitation, decision, or consequence without inventing a visible physical event.',
  continueTrack:
      'Read recent narration oldest to newest and continue directly from the last spoken line. Each beat must follow because of the previous beat: carry forward the fictional goal and unresolved snag, then use a visible detail for an attempt, complication, discovery, choice, or payoff. Develop one thread across several beats before resolving it. Do not reintroduce the protagonist or start a new story each frame. A scene change must connect to the existing thread. If history contains only the opening voiceover, inherit its exact small goal and snag; make the first visible detail serve that predicament. If a legacy opening is abstract, turn its final idea into one concrete fictional goal. Only empty history calls for a new premise.',
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
  NarrativeMemorySnapshot memory, {
  bool profiled = false,
}) {
  final normalized = name?.trim() ?? '';
  if (normalized.isEmpty) return '';
  final cadence = nameCadenceInstruction(memory, normalized);
  return 'The protagonist is named "$normalized". $cadence If the image does '
      'not clearly show a person, the name is only a narrative anchor, not '
      'evidence that the person is visible. '
      '${profiled ? '' : 'Never use a generic label such as the subject or protagonist in the spoken line.'}';
}

const _profiledDramaticInterpretation =
    'Develop the selected mode’s fictional premise and stakes through connected '
    'decisions and consequences. Fictional interpretations are story canon, '
    'not verified facts about the person. Follow the mode’s point of view and '
    'tense even if older narration used another mode.';

const _profiledContinueTrack =
    'Read recent narration oldest to newest and continue directly from the last '
    'spoken line. Carry forward its premise and unresolved stakes; each beat '
    'must advance an attempt, complication, discovery, choice, or payoff. '
    'Within two or three unchanged captures, change the fictional strategy or '
    'reach a provisional payoff. Do not invent unseen supporting characters '
    'or institutions merely to prolong a wait. If only the opening has played, '
    'establish the visible scene, then connect it to the opening’s tension. '
    'Follow the selected mode when an older premise relies on unsupported props. Keep the story '
    'through scene changes and resolve a thread before starting the next. '
    'Only empty history calls for a new premise.';
