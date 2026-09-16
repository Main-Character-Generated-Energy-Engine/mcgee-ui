import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mcgee/netlify_narration_renderer.dart';
import 'package:narration_engine/narration_engine.dart';
import 'package:narration_engine/openrouter.dart';

void main() {
  test('fetches opening credits without a camera or client-side credential', () async {
    late Map<String, dynamic> payload;
    final renderer = NetlifyNarrationRenderer(
      endpoint: Uri.parse('https://example.test/api/narrate'),
      voice: OpenRouterVoiceOption.jade,
      language: NarrationLanguage.french,
      characterName: 'Ari',
      client: MockClient((request) async {
        expect(request.headers.containsKey('Authorization'), isFalse);
        payload = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response.bytes(utf8.encode(jsonEncode({
          'title': 'Le poids des petites choses',
          'director': 'Bastien Valcour de Sève',
          'narration':
              'La vie ordinaire d’Ari mérite une attention extraordinaire.',
        })), 200);
      }),
    );

    final opening = await renderer.generateOpening();
    expect(payload, {
      'kind': 'opening',
      'language': 'fr',
      'characterName': 'Ari',
    });
    expect(opening.director, 'Bastien Valcour de Sève');
    renderer.close();
  });

  test('returns the spoken text and MP3 from the fused endpoint', () async {
    late http.Request sent;
    final renderer = NetlifyNarrationRenderer(
      endpoint: Uri.parse('https://example.test/api/narrate'),
      voice: OpenRouterVoiceOption.morganFreeman,
      language: NarrationLanguage.catalan,
      characterName: 'Ari',
      client: MockClient((request) async {
        sent = request;
        return http.Response.bytes(
          <int>[0x49, 0x44, 0x33],
          200,
          headers: <String, String>{
            'content-type': 'audio/mpeg',
            'x-narration-text': base64Url.encode(
              utf8.encode(
                'Ari considers the keyboard, then delegates the matter.',
              ),
            ),
            'x-story-state': base64Url.encode(
              utf8.encode(
                jsonEncode(<String, Object?>{
                  'storySummary': 'Ari continues the campaign at the desk.',
                  'currentActivity': 'studying the keyboard',
                  'openThread': 'finish the mysterious desk task',
                  'recurringElements': <String>[
                    'keyboard, blue edition',
                    'desk campaign',
                  ],
                }),
              ),
            ),
          },
        );
      }),
    );

    final rendered = await renderer.render(_request());

    expect(sent.headers.containsKey('Authorization'), isFalse);
    final payload = jsonDecode(sent.body) as Map<String, dynamic>;
    expect(payload['kind'], 'narration');
    expect(payload['voice'], 'morgan-freeman');
    expect(payload['language'], 'ca');
    expect(payload['characterName'], 'Ari');
    expect(payload['story']['summary'], 'Ari began the day at this desk.');
    expect(payload['story']['canon'], <String, dynamic>{
      'recurring_object': 'keyboard',
    });
    expect(payload['story']['recurringElements'], <String>[
      'keyboard, blue edition',
    ]);
    expect(payload['story']['openThread'], 'Els dits reposen sobre el teclat.');
    expect(payload['prompt'], contains('Els dits reposen sobre el teclat.'));
    expect(payload['prompt'], contains('Last spoken line'));
    expect(payload['capture']['bytesBase64'], base64Encode(<int>[1, 2, 3]));
    expect(
      rendered.draft.text,
      'Ari considers the keyboard, then delegates the matter.',
    );
    expect(
      rendered.draft.canonUpdates['open_thread'],
      'finish the mysterious desk task',
    );
    expect(rendered.draft.motifs, <String>[
      'keyboard, blue edition',
      'desk campaign',
    ]);
    expect(
      jsonDecode(rendered.draft.canonUpdates['recurring_elements']!),
      <String>['keyboard, blue edition', 'desk campaign'],
    );
    expect(rendered.track.bytes, <int>[0x49, 0x44, 0x33]);
    renderer.close();
  });

  test('synthesizes startup speech through the server endpoint', () async {
    late Map<String, dynamic> payload;
    final renderer = NetlifyNarrationRenderer(
      endpoint: Uri.parse('https://example.test/api/narrate'),
      voice: OpenRouterVoiceOption.davidAttenborough,
      language: NarrationLanguage.italian,
      characterName: 'Ari',
      client: MockClient((request) async {
        payload = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response.bytes(<int>[0x49, 0x44, 0x33], 200);
      }),
    );

    final track = await renderer.synthesize('È giunto il momento.');

    expect(payload['kind'], 'speech');
    expect(payload['voice'], 'david-attenborough');
    expect(payload['language'], 'it');
    expect(track.bytes, <int>[0x49, 0x44, 0x33]);
    renderer.close();
  });

  test('empty returned state retires resolved activity and motifs', () async {
    final renderer = NetlifyNarrationRenderer(
      endpoint: Uri.parse('https://example.test/api/narrate'),
      voice: OpenRouterVoiceOption.jade,
      language: NarrationLanguage.english,
      characterName: 'Ari',
      client: MockClient(
        (request) async => http.Response.bytes(
          <int>[0x49, 0x44, 0x33],
          200,
          headers: <String, String>{
            'x-narration-text': base64Url.encode(
              utf8.encode(
                'The notebook closes; the modest campaign is complete.',
              ),
            ),
            'x-story-state': base64Url.encode(
              utf8.encode(
                jsonEncode(<String, Object?>{
                  'storySummary': 'Ari completed the notebook campaign.',
                  'currentActivity': '',
                  'openThread': '',
                  'recurringElements': <String>[],
                }),
              ),
            ),
          },
        ),
      ),
    );

    final rendered = await renderer.render(_request());

    expect(rendered.draft.canonUpdates['current_activity'], '');
    expect(rendered.draft.canonUpdates['open_thread'], '');
    expect(rendered.draft.canonUpdates['recurring_elements'], '[]');
    renderer.close();
  });

  test('a legacy response without story state preserves existing memory', () async {
    final renderer = NetlifyNarrationRenderer(
      endpoint: Uri.parse('https://example.test/api/narrate'),
      voice: OpenRouterVoiceOption.jade,
      language: NarrationLanguage.english,
      characterName: 'Ari',
      client: MockClient(
        (request) async => http.Response.bytes(
          <int>[0x49, 0x44, 0x33],
          200,
          headers: <String, String>{
            'x-narration-text': base64Url.encode(
              utf8.encode('Ari keeps the notebook campaign alive.'),
            ),
          },
        ),
      ),
    );

    final rendered = await renderer.render(_request());

    expect(rendered.draft.canonUpdates, isEmpty);
    renderer.close();
  });

  test('surfaces endpoint failures', () async {
    final renderer = NetlifyNarrationRenderer(
      endpoint: Uri.parse('https://example.test/api/narrate'),
      voice: OpenRouterVoiceOption.morganFreeman,
      language: NarrationLanguage.english,
      characterName: 'Ari',
      client: MockClient(
        (_) async => http.Response('{"error":"Invalid credential"}', 401),
      ),
    );

    await expectLater(
      renderer.render(_request()),
      throwsA(isA<http.ClientException>()),
    );
    renderer.close();
  });
}

NarrationRequest _request() {
  final capturedAt = DateTime.utc(2026, 9, 13, 12);
  const observation = SceneObservation(
    description: 'A desk scene.',
    fingerprint: 'desk',
  );
  final memory = NarrativeMemorySnapshot(
    storySummary: 'Ari began the day at this desk.',
    canon: <String, String>{
      'recurring_object': 'keyboard',
      'recurring_elements': jsonEncode(<String>['keyboard, blue edition']),
    },
    recentNarrations: [
      NarrationMemoryEntry(
        text: 'Els dits reposen sobre el teclat.',
        observedAt: capturedAt.subtract(const Duration(seconds: 2)),
      ),
    ],
  );
  return NarrationRequest(
    prompt: const ContinuousDocumentaryPromptBuilder(
      language: NarrationLanguage.catalan,
    ).build(observation: observation, memory: memory),
    observation: observation,
    captures: <CapturedImage>[
      CapturedImage(
        source: 'webcam',
        capturedAt: capturedAt,
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
      ),
    ],
    memory: memory,
  );
}
