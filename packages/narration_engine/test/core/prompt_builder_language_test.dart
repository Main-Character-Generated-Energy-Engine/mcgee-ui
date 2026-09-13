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
    recentNarrations: <NarrationMemoryEntry>[
      NarrationMemoryEntry(
        text: 'A previous passage.',
        observedAt: DateTime.utc(2026),
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

  test('English remains the prompt builder default', () {
    final prompt = const ContinuousDocumentaryPromptBuilder(maximumWords: 20)
        .build(observation: observation, memory: memory);

    expect(prompt, contains('Write all spoken narration in English'));
    expect(prompt, contains('in 10 to 20 words'));
    expect(prompt, contains('Immediately preceding narration'));
    expect(prompt, contains('mounting crisis'));
    expect(prompt, contains("visible subject's thoughts"));
    expect(prompt, contains('exclusively in the third person'));
    expect(prompt, contains('never use first- or second-person narration'));
    expect(prompt, contains('inner monologue as indirect narration'));
    expect(prompt.toLowerCase(), isNot(contains('silence')));
  });

  test(
    'direct captures invite explicitly fictional dramatic inference',
    () async {
      final observation = await const DirectCaptureInterpreter().interpret([
        CapturedImage(
          id: 'frame.jpg',
          source: 'camera',
          capturedAt: DateTime.utc(2026),
          bytes: Uint8List.fromList([1]),
        ),
      ]);

      expect(observation.description, contains('fictional, high-stakes'));
      expect(observation.details['instruction'], contains('invent theatrical'));
      expect(
        observation.details['instruction']!.toLowerCase(),
        isNot(contains('only what is visible')),
      );
    },
  );

  test('continuous prompts carry explicit localized writing instructions', () {
    const expectedPhrases = <NarrationLanguage, String>{
      NarrationLanguage.french: 'uniquement en français',
      NarrationLanguage.spanish: 'únicamente en español',
      NarrationLanguage.italian: 'esclusivamente in italiano',
      NarrationLanguage.catalan: 'exclusivament en català',
    };

    for (final entry in expectedPhrases.entries) {
      final prompt = ContinuousDocumentaryPromptBuilder(
        maximumWords: 20,
        language: entry.key,
      ).build(observation: observation, memory: memory);

      expect(prompt, contains(entry.value), reason: entry.key.nativeName);
      expect(prompt, contains('10'), reason: entry.key.nativeName);
      expect(prompt, contains('20'), reason: entry.key.nativeName);
      expect(prompt, contains('A previous passage.'));
    }
  });

  test('all localized prompts demand grave third-person voiceover', () {
    const expectedDramaPhrases = <NarrationLanguage, String>{
      NarrationLanguage.english: 'something grave is seconds away',
      NarrationLanguage.french: 'Quelque chose de grave',
      NarrationLanguage.spanish: 'algo grave está a punto de ocurrir',
      NarrationLanguage.italian: 'qualcosa di grave è imminente',
      NarrationLanguage.catalan: 'alguna cosa greu és imminent',
    };
    const forbiddenEditorialChoices = <String>[
      'silence',
      'silencio',
      'silenzio',
      'silenci',
    ];
    const expectedPerspectivePhrases = <NarrationLanguage, String>{
      NarrationLanguage.english: 'first- or second-person narration',
      NarrationLanguage.french: 'la première ni la deuxième personne',
      NarrationLanguage.spanish: 'la primera ni la segunda persona',
      NarrationLanguage.italian: 'la prima né la seconda persona',
      NarrationLanguage.catalan: 'la primera ni la segona persona',
    };

    for (final entry in expectedDramaPhrases.entries) {
      final standardPrompt = DocumentaryPromptBuilder(
        maximumWords: 24,
        language: entry.key,
      ).build(observation: observation, memory: memory);
      final continuousPrompt = ContinuousDocumentaryPromptBuilder(
        maximumWords: 20,
        language: entry.key,
      ).build(observation: observation, memory: memory);

      expect(
        standardPrompt,
        contains(entry.value),
        reason: entry.key.nativeName,
      );
      expect(
        standardPrompt.toLowerCase(),
        contains(expectedPerspectivePhrases[entry.key]!.toLowerCase()),
        reason: entry.key.nativeName,
      );
      for (final forbidden in forbiddenEditorialChoices) {
        expect(
          standardPrompt.toLowerCase(),
          isNot(contains(forbidden)),
          reason: entry.key.nativeName,
        );
        expect(
          continuousPrompt.toLowerCase(),
          isNot(contains(forbidden)),
          reason: entry.key.nativeName,
        );
      }
    }
  });

  test(
    'provider-level writing instructions use the selected language',
    () async {
      final api = _CapturingApi();
      await OpenAiNarrationModel(
        client: api,
        requireSpokenLine: true,
        language: NarrationLanguage.french,
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
        contains('grandiloquent urgency'),
      );
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
          '{"action":"speak","text":"Il avance.","reason":"",'
          '"motifs":[],"canon_updates":[]}',
    };
  }

  @override
  Future<Uint8List> createSpeech(Map<String, Object?> body) =>
      throw UnimplementedError();
}
