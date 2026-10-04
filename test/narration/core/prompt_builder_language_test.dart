import 'dart:typed_data';

import 'package:mcgee/narration_engine.dart';
import 'package:mcgee/src/openai/openai_http_client.dart';
import 'package:mcgee/src/openai/openai_narration_model.dart';
import 'package:test/test.dart';

void main() {
  const observation = SceneObservation(
    description: 'The protagonist reaches for a mug.',
    fingerprint: 'mug',
  );
  final memory = NarrativeMemorySnapshot(
    storySummary: 'Ari began an overly serious campaign to conquer the desk.',
    recentNarrations: [
      NarrationMemoryEntry(
        text: 'The mug waits beneath an outstretched hand.',
        observedAt: DateTime.utc(2026),
      ),
    ],
    canon: const {'mug': 'a recurring adversary'},
  );

  test('language API values round-trip', () {
    for (final language in NarrationLanguage.values) {
      expect(NarrationLanguage.fromApiValue(language.apiValue), language);
      expect(language.writerInstruction, isNotEmpty);
    }
  });

  test('prompt builders supply only scene and story data', () {
    final standard = const DocumentaryPromptBuilder()
        .build(observation: observation, memory: memory);
    final continuous = const ContinuousDocumentaryPromptBuilder()
        .build(observation: observation, memory: memory);
    expect(continuous, standard);
    expect(continuous, contains('The protagonist reaches for a mug.'));
    expect(continuous, contains('mug: a recurring adversary'));
    expect(continuous, contains('Ari began an overly serious campaign'));
    expect(continuous, contains('Last spoken line — continue this beat:\n'
        'The mug waits beneath an outstretched hand.'));
    expect(continuous, isNot(contains('Write all spoken narration')));
    expect(continuous, isNot(contains('Ground every line')));
  });

  test(
    'story state survives unchanged frames and transcript rollover',
    () async {
      final story = NarrativeMemory(maxNarrations: 2);
      story.recordNarration(
        text: 'I remembered Ari waiting for certainty before beginning.',
        observedAt: DateTime.utc(2026),
        canonUpdates: const {
          'story_goal': 'Fiction: begin despite uncertainty',
          'story_obstacle': 'Fiction: fear of an imperfect start',
          'open_thread': 'Will Ari accept an imperfect start?',
        },
      );
      for (var beat = 0; beat < 4; beat++) {
        story.recordObservation(observation);
        story.recordNarration(
          text: 'Inner beat $beat.',
          observedAt: DateTime.utc(2026, 1, 1, 0, beat + 1),
          canonUpdates: {'latest_development': 'Fiction: approach $beat'},
        );
      }
      final api = _CapturingApi();
      final snapshot = story.snapshot;
      await OpenAiNarrationModel(client: api).narrate(
        NarrationRequest(
          prompt: const ContinuousDocumentaryPromptBuilder().build(
            observation: observation,
            memory: snapshot,
          ),
          observation: observation,
          captures: const [],
          memory: snapshot,
        ),
      );
      final input = api.responseBody['input'] as String;
      expect(snapshot.recentNarrations, hasLength(2));
      expect(
        input,
        contains('Story goal:\nFiction: begin despite uncertainty'),
      );
      expect(
        input,
        contains('Story obstacle:\nFiction: fear of an imperfect start'),
      );
      expect(
        input,
        contains('Latest spoken development:\nFiction: approach 3'),
      );
      expect(
        input,
        contains('Open story thread:\nWill Ari accept an imperfect start?'),
      );
      expect(
        input,
        contains('Last spoken line — continue this beat:\nInner beat 3.'),
      );
    },
  );

  test('provider owns language, mode, name preference, and length rules', () async {
    final api = _CapturingApi();
    final model = OpenAiNarrationModel(
      client: api,
      continuous: true,
      maximumWords: 20,
      language: NarrationLanguage.french,
      characterName: 'Ari',
      narratorInstructions: () => 'Tell the recollection in past tense.',
    );
    final prompt = const ContinuousDocumentaryPromptBuilder()
        .build(observation: observation, memory: memory);
    await model.narrate(NarrationRequest(
      prompt: prompt,
      observation: observation,
      captures: const [],
      memory: memory,
    ));
    final instructions = api.responseBody['instructions'] as String;
    expect(instructions, contains('Tell the recollection in past tense.'));
    expect(instructions, contains('only in French'));
    expect(instructions, contains('named "Ari"'));
    expect(instructions, contains('Use the name occasionally'));
    expect(instructions, contains('10 to 20 words'));
    expect(api.responseBody['input'], prompt);
  });

  test('first passage length instruction is held in the provider', () async {
    final api = _CapturingApi();
    final model = OpenAiNarrationModel(
      client: api,
      continuous: true,
      maximumWords: 20,
      narratorInstructions: () => 'A past-tense recollection.',
    );
    final opening = NarrativeMemorySnapshot(recentNarrations: [
      NarrationMemoryEntry(
        text: 'I remembered Ari wanting certainty before he could begin.',
        observedAt: DateTime.utc(2026),
      ),
    ]);
    await model.narrate(NarrationRequest(
      prompt: 'Continue.', observation: observation,
      captures: const [], memory: opening,
    ));
    expect(api.responseBody['instructions'], contains('25 to 35 words'));
  });

  test('direct capture interpreter contributes a marker, not editorial rules', () async {
    final scene = await const DirectCaptureInterpreter().interpret([
      CapturedImage(
        id: 'frame.jpg',
        source: 'camera',
        capturedAt: DateTime.utc(2026),
        bytes: Uint8List.fromList([1]),
      ),
    ]);
    expect(scene.description, contains('Latest capture: frame.jpg'));
    expect(scene.details, isEmpty);
  });
}

final class _CapturingApi implements OpenAiApi {
  Map<String, Object?> responseBody = const {};

  @override
  Future<Map<String, Object?>> createResponse(Map<String, Object?> body) async {
    responseBody = body;
    return {
      'output_text':
          '{"action":"speak","text":"Ari avance.","reason":"",'
          '"motifs":[],"canon_updates":[]}',
    };
  }
}
