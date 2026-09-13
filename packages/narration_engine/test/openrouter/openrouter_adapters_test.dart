import 'dart:typed_data';

import 'package:narration_engine/src/core/models.dart';
import 'package:narration_engine/src/openai/openai_http_client.dart';
import 'package:narration_engine/src/openrouter/openrouter_narration_model.dart';
import 'package:narration_engine/src/openrouter/openrouter_speech_synthesizer.dart';
import 'package:narration_engine/src/openrouter/openrouter_voice_option.dart';
import 'package:test/test.dart';

void main() {
  test(
    'uses OpenRouter model slugs and Morgan Freeman speech by default',
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
      final track = await OpenRouterSpeechSynthesizer(client: api)
          .synthesize(draft.text!);

      final narrationBody = api.responseBodies.single;
      expect(narrationBody['model'], 'openai/gpt-5.6-sol');
      expect(narrationBody['max_output_tokens'], 150);
      expect(narrationBody['reasoning'], {'effort': 'none'});
      expect(
        narrationBody['instructions'],
        contains('10 to 20 words in one commanding sentence'),
      );
      expect(narrationBody['instructions'], contains('grandiloquent urgency'));
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
      expect(api.speechBodies.single, {
        'model': 'fish-audio/s2.1-pro',
        'voice': '3ad4d432023c47ee9e6c7805b973630a',
        'input': 'The campaign advances by inches.',
        'response_format': 'mp3',
      });
      expect(track.bytes, [0x49, 0x44, 0x33]);
    },
  );

  test('keeps actor voices paired with their provider models', () async {
    final api = _FakeOpenRouterApi();
    final options = <OpenRouterVoiceOption>[
      OpenRouterVoiceOption.morganFreeman,
      OpenRouterVoiceOption.davidAttenborough,
      OpenRouterVoiceOption.jade,
    ];

    for (final option in options) {
      await OpenRouterSpeechSynthesizer.withVoice(
        client: api,
        voice: option,
      ).synthesize('A brief field note.');
    }

    expect(api.speechBodies.map((body) => body['model']), [
      'fish-audio/s2.1-pro',
      'fish-audio/s2.1-pro',
      'x-ai/grok-voice-tts-1.0',
    ]);
    expect(api.speechBodies.map((body) => body['voice']), [
      '3ad4d432023c47ee9e6c7805b973630a',
      'c39a76f685cf4f8fb41cd5d3d66b497d',
      'eve',
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
    expect(body['model'], 'openai/gpt-5.6-sol');
    expect(body['max_output_tokens'], 80);
    expect(body['text'], isNull);
    expect(
      body['instructions'],
      contains('Output only the exact words to speak'),
    );
    expect(body['instructions'], contains('grandiloquent urgency'));
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

  @override
  Future<Uint8List> createSpeech(Map<String, Object?> body) {
    throw UnimplementedError();
  }
}

final class _FakeOpenRouterApi implements OpenAiApi {
  final List<Map<String, Object?>> responseBodies = [];
  final List<Map<String, Object?>> speechBodies = [];

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

  @override
  Future<Uint8List> createSpeech(Map<String, Object?> body) async {
    speechBodies.add(body);
    return Uint8List.fromList([0x49, 0x44, 0x33]);
  }
}
