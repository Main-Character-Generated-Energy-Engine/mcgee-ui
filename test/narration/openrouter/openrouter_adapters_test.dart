import 'dart:typed_data';

import 'package:mcgee/src/core/models.dart';
import 'package:mcgee/src/openai/openai_http_client.dart';
import 'package:mcgee/src/openrouter/openrouter_narration_model.dart';
import 'package:mcgee/src/openrouter/openrouter_voice_option.dart';
import 'package:test/test.dart';

void main() {
  test(
    'uses the OpenRouter writing model by default',
    () async {
      final api = _FakeOpenRouterApi();
      final capture = CapturedImage(
        id: '10.jpg',
        source: 'webcam',
        capturedAt: DateTime.fromMillisecondsSinceEpoch(10000, isUtc: true),
        bytes: Uint8List.fromList([0xff, 0xd8, 0xff]),
        protagonistHint: 'the foreground camera holder',
      );

      final draft =
          await OpenRouterNarrationModel(
            client: api,
            requireSpokenLine: true,
            includeCaptures: true,
            continuous: true,
            maximumWords: 20,
          ).narrate(
            NarrationRequest(
              prompt: 'A test prompt',
              observation: const SceneObservation(
                description: 'The latest live camera frame.',
                fingerprint: 'live-frame',
              ),
              captures: [capture],
              memory: const NarrativeMemorySnapshot(),
            ),
          );
      expect(draft.text, 'The campaign advances by inches.');

      final narrationBody = api.responseBodies.single;
      expect(narrationBody['model'], 'openai/gpt-5.6-terra');
      expect(narrationBody['max_output_tokens'], 1200);
      expect(narrationBody['reasoning'], {'effort': 'medium'});
      expect(
        narrationBody['instructions'],
        contains('10 to 20 words in one confident, complete sentence'),
      );
      expect(
        narrationBody['instructions'],
        contains('Invent and sustain character motives'),
      );
      final narrationInput = narrationBody['input'] as List;
      final narrationContent =
          (narrationInput.single as Map)['content'] as List;
      final narrationImage = narrationContent.whereType<Map>().singleWhere(
        (part) => part['type'] == 'input_image',
      );
      expect(
        narrationImage['image_url'],
        startsWith('data:image/jpeg;base64,'),
      );
    },
  );

  test('OpenRouter forwards selected mode for structured and streamed writing', () async {
    var mode = 'Past-tense recollection; the narrator may say I.';
    final api = _FakeStreamingOpenRouterApi();
    final structuredApi = _FakeOpenRouterApi();
    final model = OpenRouterNarrationModel(
      client: structuredApi,
      narratorInstructions: () => mode,
    );
    final streamingModel = OpenRouterNarrationModel(
      client: api,
      requireSpokenLine: true,
      narratorInstructions: () => mode,
    );
    const request = NarrationRequest(
      prompt: 'Continue the earlier story.',
      observation: SceneObservation(description: 'A visible mug.', fingerprint: 'mug'),
      captures: [],
      memory: NarrativeMemorySnapshot(),
    );
    for (final nextMode in [mode, 'Present-tense survival documentary.', 'Current breaking-news coverage.']) {
      mode = nextMode;
      await model.narrate(request);
      final stream = await streamingModel.narrateStream(request);
      await stream.textDeltas.drain<void>();
      await stream.completed;
      for (final body in [structuredApi.responseBodies.last, api.streamingResponseBodies.last]) {
        expect(body['instructions'], contains(mode));
        expect(body['instructions'], isNot(contains('exclusively in the third person')));
        expect(body['instructions'], isNot(contains('Keep the stakes small')));
      }
    }
  });

  test('keeps every actor voice on Fish s2.1-pro-free', () {
    final options = <OpenRouterVoiceOption>[
      OpenRouterVoiceOption.morganFreeman,
      OpenRouterVoiceOption.davidAttenborough,
      OpenRouterVoiceOption.jade,
    ];

    expect(options.map((option) => option.model), [
      's2.1-pro-free', 's2.1-pro-free', 's2.1-pro-free',
    ]);
    expect(options.map((option) => option.voiceId), [
      '3ad4d432023c47ee9e6c7805b973630a',
      'c39a76f685cf4f8fb41cd5d3d66b497d',
      '1e5902ed8ddf433b88a717444bb90510',
    ]);
  });

  test('streams plain narration deltas and completes a valid draft', () async {
    final api = _FakeStreamingOpenRouterApi();
    final stream =
        await OpenRouterNarrationModel(
          client: api,
          requireSpokenLine: true,
          continuous: true,
          maximumWords: 20,
        ).narrateStream(
          const NarrationRequest(
            prompt: 'Narrate this scene.',
            observation: SceneObservation(
              description: 'Someone waits beside a kettle.',
              fingerprint: 'waiting-kettle',
            ),
            captures: [],
            memory: NarrativeMemorySnapshot(),
          ),
        );

    expect(await stream.textDeltas.toList(), [
      'The kettle',
      ' maintains',
      ' the upper hand.',
    ]);
    final draft = await stream.completed;
    expect(draft.shouldSpeak, isTrue);
    expect(draft.text, 'The kettle maintains the upper hand.');
    expect(draft.motifs, isEmpty);
    expect(draft.canonUpdates, isEmpty);

    final body = api.streamingResponseBodies.single;
    expect(body['model'], 'openai/gpt-5.6-terra');
    expect(body['max_output_tokens'], 1200);
    expect(body['text'], isNull);
    expect(
      body['instructions'],
      contains('Output only the exact words to speak'),
    );
    expect(body['instructions'], contains('Invent and sustain character motives'));
    expect(
      (body['instructions'] as String).toLowerCase(),
      isNot(contains('silence')),
    );
  });

  test('requires an unconditional spoken line for streaming', () async {
    final model = OpenRouterNarrationModel(
      client: _FakeStreamingOpenRouterApi(),
    );

    await expectLater(
      model.narrateStream(
        const NarrationRequest(
          prompt: 'Narrate this scene.',
          observation: SceneObservation(
            description: 'An unchanged room.',
            fingerprint: 'room',
          ),
          captures: [],
          memory: NarrativeMemorySnapshot(),
        ),
      ),
      throwsStateError,
    );
  });

  test('finds bundled voice options case-insensitively', () {
    expect(
      OpenRouterVoiceOption.named('Morgan-Freeman'),
      OpenRouterVoiceOption.morganFreeman,
    );
    expect(
      OpenRouterVoiceOption.named('David-Attenborough'),
      OpenRouterVoiceOption.davidAttenborough,
    );
    expect(OpenRouterVoiceOption.named('unknown'), isNull);
  });
}

final class _FakeStreamingOpenRouterApi implements StreamingOpenAiApi {
  final List<Map<String, Object?>> streamingResponseBodies = [];

  @override
  Stream<Map<String, Object?>> createResponseStream(
    Map<String, Object?> body,
  ) async* {
    streamingResponseBodies.add(body);
    yield {'type': 'response.content_part.delta', 'delta': 'The kettle'};
    yield {'type': 'response.output_text.delta', 'delta': ' maintains'};
    yield {'type': 'response.output_text.delta', 'delta': ' the upper hand.'};
    yield {
      'type': 'response.completed',
      'response': {'status': 'completed'},
    };
  }

  @override
  Future<Map<String, Object?>> createResponse(Map<String, Object?> body) {
    throw UnimplementedError();
  }
}

final class _FakeOpenRouterApi implements OpenAiApi {
  final List<Map<String, Object?>> responseBodies = [];

  @override
  Future<Map<String, Object?>> createResponse(Map<String, Object?> body) async {
    responseBodies.add(body);
    return {
      'output_text':
          '{"action":"speak","text":"The campaign advances by inches.",'
          '"reason":"A visible change.","motifs":["campaign"],'
          '"canon_updates":[]}',
    };
  }
}
