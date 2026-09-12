import 'dart:typed_data';

import 'package:narration_engine/src/core/models.dart';
import 'package:narration_engine/src/openai/openai_http_client.dart';
import 'package:narration_engine/src/openrouter/openrouter_narration_model.dart';
import 'package:narration_engine/src/openrouter/openrouter_scene_interpreter.dart';
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

      final observation = await OpenRouterSceneInterpreter(client: api)
          .interpret([capture]);
      final draft =
          await OpenRouterNarrationModel(
            client: api,
            requireSpokenLine: true,
          ).narrate(
            NarrationRequest(
              prompt: 'A test prompt',
              observation: observation,
              captures: [capture],
              memory: const NarrativeMemorySnapshot(),
            ),
          );
      final track = await OpenRouterSpeechSynthesizer(client: api)
          .synthesize(draft.text!);

      expect(api.responseBodies.first['model'], 'openai/gpt-4.1-mini');
      expect(api.responseBodies.first['max_output_tokens'], 500);
      expect(api.responseBodies[1]['model'], 'openai/gpt-5.6-sol');
      expect(api.responseBodies[1]['max_output_tokens'], 400);
      expect(api.speechBodies.single, {
        'model': 'fish-audio/s2.1-pro',
        'voice': 'bb742915b1fa41b389a850b11efae0c8',
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
      'bb742915b1fa41b389a850b11efae0c8',
      'c39a76f685cf4f8fb41cd5d3d66b497d',
      'eve',
    ]);
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

String _schemaName(Map<String, Object?> body) {
  final text = body['text'] as Map;
  final format = text['format'] as Map;
  return format['name'] as String;
}

final class _FakeOpenRouterApi implements OpenAiApi {
  final List<Map<String, Object?>> responseBodies = [];
  final List<Map<String, Object?>> speechBodies = [];

  @override
  Future<Map<String, Object?>> createResponse(Map<String, Object?> body) async {
    responseBodies.add(body);
    if (_schemaName(body) == 'scene_observation') {
      return {
        'output_text':
            '{"description":"A person turns while seated.",'
            '"fingerprint":"desk-turning","salience":0.6,'
            '"setting":"room","action":"turning",'
            '"visible_subjects":"one person",'
            '"temporal_change":"the person turns",'
            '"focal_capture_id":"10.jpg"}',
      };
    }
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
