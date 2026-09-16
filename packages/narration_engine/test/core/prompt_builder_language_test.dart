import 'dart:typed_data';

import 'package:narration_engine/narration_engine.dart';
import 'package:narration_engine/src/openai/openai_http_client.dart';
import 'package:narration_engine/src/openai/openai_narration_model.dart';
import 'package:test/test.dart';

void main() {
  const observation = SceneObservation(
    description: 'The protagonist reaches for a mug.',
    fingerprint: 'mug',
  );
  final memory = NarrativeMemorySnapshot(
    storySummary: 'Ari began an overly serious campaign to conquer the desk.',
    recentNarrations: <NarrationMemoryEntry>[
      NarrationMemoryEntry(
        text: 'A previous passage.',
        observedAt: DateTime.utc(2026),
      ),
      NarrationMemoryEntry(
        text: 'The mug waits beneath an outstretched hand.',
        observedAt: DateTime.utc(2026, 1, 1, 0, 0, 2),
      ),
    ],
    canon: const <String, String>{'mug': 'a recurring adversary'},
  );

  test('language API values round-trip and invalid values fail', () {
    for (final language in NarrationLanguage.values) {
      expect(NarrationLanguage.fromApiValue(language.apiValue), language);
      expect(language.nativeName, isNotEmpty);
      expect(language.startupLine, isNotEmpty);
      expect(language.writerInstruction, isNotEmpty);
    }

    expect(
      () => NarrationLanguage.fromApiValue('de'),
      throwsA(isA<FormatException>()),
    );
  });

  test('mode changes preserve history without conflicting point of view', () async {
    var mode = 'Morgan mode: tell the recollection in past tense; I is allowed.';
    final builder = ContinuousDocumentaryPromptBuilder(
      characterName: 'Ari',
      narratorInstructions: () => mode,
    );
    final api = _CapturingApi();
    final model = OpenAiNarrationModel(
      client: api,
      characterName: 'Ari',
      narratorInstructions: () => mode,
    );
    for (final nextMode in [mode, 'David mode: present-tense specimen survival.', 'Eve mode: current live news.']) {
      mode = nextMode;
      final prompt = builder.build(observation: observation, memory: memory);
      expect(prompt, contains(mode));
      expect(prompt, contains('The mug waits beneath an outstretched hand.'));
      expect(prompt, contains('mug: a recurring adversary'));
      expect(prompt, isNot(contains('exclusively in the third person')));
      expect(prompt, isNot(contains('exact small goal')));
      expect(prompt, isNot(contains('Never use a generic label')));
      await model.narrate(NarrationRequest(
        prompt: prompt,
        observation: observation,
        captures: const [],
        memory: memory,
      ));
      final instructions = api.responseBody['instructions'] as String;
      expect(instructions, contains(mode));
      expect(instructions, contains('Use the supplied character name exactly once'));
      expect(instructions, isNot(contains('exclusively in the third person')));
      expect(instructions, isNot(contains('Keep the stakes small')));
    }
  });

  test('English remains the prompt builder default', () {
    final prompt = const ContinuousDocumentaryPromptBuilder(maximumWords: 20)
        .build(observation: observation, memory: memory);

    expect(prompt, contains('Write all spoken narration only in English'));
    expect(prompt, contains('in 10 to 20 words'));
    expect(prompt, contains('Immediately preceding narration'));
    expect(
      prompt,
      contains(
        'Last spoken line — continue this beat:\n'
        'The mug waits beneath an outstretched hand.',
      ),
    );
    expect(prompt, contains('continue directly from the last spoken line'));
    expect(prompt, contains("visible subject's actions"));
    expect(prompt, contains('exclusively in the third person'));
    expect(prompt, contains('never use first- or second-person narration'));
    expect(prompt, contains('inner monologue as indirect narration'));
    expect(prompt.toLowerCase(), isNot(contains('silence')));
  });

  test('names the protagonist and carries the older story recap', () {
    final prompt = const ContinuousDocumentaryPromptBuilder(
      maximumWords: 20,
      characterName: 'Ari',
    ).build(observation: observation, memory: memory);

    expect(prompt, contains('The protagonist is named "Ari"'));
    expect(prompt, contains('Use the supplied character name exactly once'));
    expect(prompt, contains('Story so far — older spoken beats'));
    expect(prompt, contains('Ari began an overly serious campaign'));
  });

  test(
    'direct captures anchor the ongoing fiction in visual evidence',
    () async {
      final observation = await const DirectCaptureInterpreter().interpret([
        CapturedImage(
          id: 'frame.jpg',
          source: 'camera',
          capturedAt: DateTime.utc(2026),
          bytes: Uint8List.fromList([1]),
        ),
      ]);

      expect(observation.description, contains('current visible action'));
      expect(
        observation.details['instruction'],
        contains('concrete action or posture'),
      );
      expect(
        observation.details['instruction']!.toLowerCase(),
        contains('do not invent unseen actions'),
      );
    },
  );

  test('all output languages share the same English editorial prompts', () {
    final defaultStandard = const DocumentaryPromptBuilder(maximumWords: 24)
        .build(observation: observation, memory: memory);
    final defaultContinuous = const ContinuousDocumentaryPromptBuilder(
      maximumWords: 20,
    ).build(observation: observation, memory: memory);

    for (final language in NarrationLanguage.values) {
      final standard = DocumentaryPromptBuilder(
        maximumWords: 24,
        language: language,
      ).build(observation: observation, memory: memory);
      final continuous = ContinuousDocumentaryPromptBuilder(
        maximumWords: 20,
        language: language,
      ).build(observation: observation, memory: memory);

      for (final prompt in [standard, continuous]) {
        expect(prompt, contains('only in ${language.englishName}'));
        expect(prompt, contains('do not translate an English draft'));
        expect(prompt, contains('Ground every line in the current capture'));
        expect(prompt, contains('first- or second-person narration'));
        expect(prompt, contains('Last spoken line — continue this beat'));
        expect(prompt, contains('The mug waits beneath an outstretched hand.'));
        expect(prompt, contains('mug: a recurring adversary'));
        expect(prompt.toLowerCase(), isNot(contains('silence')));
      }
      // The target language directive is the only changing instruction.
      expect(
        standard.replaceAll(language.writerInstruction, ''),
        defaultStandard.replaceAll(NarrationLanguage.english.writerInstruction, ''),
      );
      expect(
        continuous.replaceAll(language.writerInstruction, ''),
        defaultContinuous.replaceAll(NarrationLanguage.english.writerInstruction, ''),
      );
    }
  });

  test('English context labels preserve previously spoken non-English text', () {
    final prompt = const ContinuousDocumentaryPromptBuilder(
      language: NarrationLanguage.catalan,
    ).build(
      observation: observation,
      memory: NarrativeMemorySnapshot(
        recentNarrations: [
          NarrationMemoryEntry(
            text: 'Els dits reposen sobre el teclat.',
            observedAt: DateTime.utc(2026),
          ),
        ],
      ),
    );
    expect(prompt, contains('Current observation:'));
    expect(prompt, contains('Last spoken line — continue this beat:\n'
        'Els dits reposen sobre el teclat.'));
    expect(prompt, contains('only in Catalan'));
    expect(prompt, isNot(contains('only in English')));
  });

  test(
    'provider-level writing instructions use the selected language',
    () async {
      final api = _CapturingApi();
      await OpenAiNarrationModel(
        client: api,
        requireSpokenLine: true,
        language: NarrationLanguage.french,
        characterName: 'Ari',
      ).narrate(
        NarrationRequest(
          prompt: 'Continue.',
          observation: observation,
          captures: const <CapturedImage>[],
          memory: const NarrativeMemorySnapshot(),
        ),
      );

      expect(
        api.responseBody['instructions'],
        contains(NarrationLanguage.french.writerInstruction),
      );
      expect(
        api.responseBody['instructions'],
        contains('Invent and sustain character motives'),
      );
      expect(api.responseBody['instructions'], contains('named "Ari"'));
      expect(
        (api.responseBody['instructions'] as String).toLowerCase(),
        isNot(contains('silence')),
      );
    },
  );
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

  @override
  Future<Uint8List> createSpeech(Map<String, Object?> body) =>
      throw UnimplementedError();
}
