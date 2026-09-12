import 'dart:typed_data';

import 'package:narration_engine/src/core/models.dart';
import 'package:narration_engine/src/openai/openai_http_client.dart';
import 'package:narration_engine/src/openai/openai_narration_model.dart';
import 'package:narration_engine/src/openai/openai_scene_interpreter.dart';
import 'package:narration_engine/src/openai/openai_speech_synthesizer.dart';
import 'package:test/test.dart';

void main() {
  test('parses a provider-neutral scene observation', () {
    final observation = parseSceneObservation(
      {
        'output': [
          {
            'type': 'message',
            'content': [
              {
                'type': 'output_text',
                'text': '''
{"description":"A person remains seated while turning toward a nearby object.","fingerprint":"desk-turning","salience":0.6,"setting":"room with desk","action":"turning while seated","visible_subjects":"one person","temporal_change":"head and upper body turn","focal_capture_id":"20.jpg"}
''',
              },
            ],
          },
        ],
      },
      {'10.jpg', '20.jpg'},
    );

    expect(observation.fingerprint, 'desk-turning');
    expect(observation.salience, 0.6);
    expect(observation.details['focal_capture_id'], '20.jpg');
  });

  test('rejects an unknown focal capture ID', () {
    expect(
      () => parseSceneObservation(
        {
          'output_text':
              '{"description":"Still room.","fingerprint":"room-still",'
              '"salience":0.1,"setting":"room","action":"none",'
              '"visible_subjects":"person","temporal_change":"none",'
              '"focal_capture_id":"missing.jpg"}',
        },
        {'10.jpg'},
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('parses a spoken narration decision', () {
    final draft = parseNarrationDraft({
      'output_text':
          '{"action":"speak","text":"The campaign advances by inches.",'
          '"reason":"A visible turn provides a beat.",'
          '"motifs":["territorial campaign"],'
          '"canon_updates":[{"key":"desk","value":"the eastern frontier"}]}',
    });

    expect(draft.shouldSpeak, isTrue);
    expect(draft.text, 'The campaign advances by inches.');
    expect(draft.motifs, ['territorial campaign']);
    expect(draft.canonUpdates['desk'], 'the eastern frontier');
  });

  test('parses silence as a successful narration decision', () {
    final draft = parseNarrationDraft({
      'output_text':
          '{"action":"silence","text":"","reason":"No meaningful change.",'
          '"motifs":[],"canon_updates":[]}',
    });

    expect(draft.shouldSpeak, isFalse);
    expect(draft.reason, 'No meaningful change.');
  });

  test(
    'adapters send current Responses and Speech API request shapes',
    () async {
      final api = _FakeOpenAiApi();
      final capture = CapturedImage(
        id: '10.jpg',
        source: 'webcam',
        capturedAt: DateTime.fromMillisecondsSinceEpoch(10000, isUtc: true),
        bytes: Uint8List.fromList([0xff, 0xd8, 0xff]),
        protagonistHint: 'the foreground camera holder',
      );
      final observation = await OpenAiSceneInterpreter(client: api)
          .interpret([capture]);
      final draft =
          await OpenAiNarrationModel(
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
      final track = await OpenAiSpeechSynthesizer(client: api)
          .synthesize(draft.text!);

      final sceneBody = api.responseBodies.first;
      expect(sceneBody['max_output_tokens'], 500);
      expect(sceneBody['store'], isFalse);
      expect(_schemaName(sceneBody), 'scene_observation');
      final input = sceneBody['input'] as List;
      final content = (input.single as Map)['content'] as List;
      expect(
        (content.first as Map)['text'],
        contains('foreground camera holder'),
      );
      final image = content.whereType<Map>().singleWhere(
        (part) => part['type'] == 'input_image',
      );
      expect(image['image_url'], startsWith('data:image/jpeg;base64,'));

      expect(api.responseBodies[1]['store'], isFalse);
      expect(api.responseBodies[1]['max_output_tokens'], 400);
      expect(_schemaName(api.responseBodies[1]), 'narration_decision');
      expect(api.speechBodies.single['response_format'], 'mp3');
      expect(api.speechBodies.single['model'], 'gpt-4o-mini-tts');
      expect(track.bytes, [0x49, 0x44, 0x33]);
    },
  );
}

String _schemaName(Map<String, Object?> body) {
  final text = body['text'] as Map;
  final format = text['format'] as Map;
  return format['name'] as String;
}

final class _FakeOpenAiApi implements OpenAiApi {
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
