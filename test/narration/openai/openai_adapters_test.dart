import 'dart:typed_data';

import 'package:mcgee/src/core/models.dart';
import 'package:mcgee/src/openai/openai_http_client.dart';
import 'package:mcgee/src/openai/openai_narration_model.dart';
import 'package:test/test.dart';

void main() {
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
    'adapter sends the current Responses API request shape',
    () async {
      final api = _FakeOpenAiApi();
      final capture = CapturedImage(
        id: '10.jpg',
        source: 'webcam',
        capturedAt: DateTime.fromMillisecondsSinceEpoch(10000, isUtc: true),
        bytes: Uint8List.fromList([0xff, 0xd8, 0xff]),
        protagonistHint: 'the foreground camera holder',
      );
      final draft =
          await OpenAiNarrationModel(
            client: api,
            requireSpokenLine: true,
            includeCaptures: true,
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
      expect(narrationBody['model'], 'gpt-5.6-terra');
      expect(narrationBody['max_output_tokens'], 1200);
      expect(narrationBody['reasoning'], {'effort': 'medium'});
      expect(narrationBody['store'], isFalse);
      expect(_schemaName(narrationBody), 'narration_decision');
      expect(
        narrationBody['instructions'],
        contains('Invent and sustain character motives'),
      );
      expect(
        (narrationBody['instructions'] as String).toLowerCase(),
        isNot(contains('silence')),
      );
      final text = narrationBody['text'] as Map;
      final format = text['format'] as Map;
      final schema = format['schema'] as Map;
      final properties = schema['properties'] as Map;
      final action = properties['action'] as Map;
      expect(action['enum'], ['speak']);
      final input = narrationBody['input'] as List;
      final content = (input.single as Map)['content'] as List;
      expect(
        content.whereType<Map>().where((part) => part['type'] == 'input_text'),
        contains(
          predicate<Map>(
            (part) =>
                (part['text'] as String).contains('foreground camera holder'),
          ),
        ),
      );
      final image = content.whereType<Map>().singleWhere(
        (part) => part['type'] == 'input_image',
      );
      expect(image['image_url'], startsWith('data:image/jpeg;base64,'));
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
