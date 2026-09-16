import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mcgee/netlify_narration_renderer.dart';
import 'package:narration_engine/narration_engine.dart';
import 'package:narration_engine/openrouter.dart';

void main() {
  test('exposes audio before the response finishes and preserves chunk order', () async {
    final body = StreamController<List<int>>();
    final renderer = _streamRenderer(MockClient.streaming((request, _) async {
      return http.StreamedResponse(body.stream, 200, headers: _streamHeaders);
    }));
    final rendered = await renderer.render(_request());
    final chunks = StreamIterator(rendered.track.stream!);
    body.add([1, 2, 3]);
    expect(await chunks.moveNext(), isTrue);
    expect(chunks.current, [1, 2, 3]);
    expect(body.isClosed, isFalse);
    body.add([4, 5]);
    unawaited(body.close());
    expect(await chunks.moveNext(), isTrue);
    expect(chunks.current, [4, 5]);
    expect(await chunks.moveNext(), isFalse);
    await rendered.track.dispose();
    renderer.close();
  });

  test('disposing an unplayed stream cancels the HTTP request', () async {
    var canceled = false;
    late Future<void> aborted;
    final body = StreamController<List<int>>(onCancel: () { canceled = true; });
    final renderer = _streamRenderer(MockClient.streaming((request, _) async {
      aborted = (request as http.AbortableRequest).abortTrigger!;
      return http.StreamedResponse(body.stream, 200, headers: _streamHeaders);
    }));
    final rendered = await renderer.render(_request());
    await rendered.track.dispose();
    await aborted;
    expect(canceled, isTrue);
    unawaited(body.close());
    renderer.close();
  });

  test('stream errors reach playback after a valid first chunk', () async {
    final body = StreamController<List<int>>();
    final renderer = _streamRenderer(MockClient.streaming((_, _) async =>
        http.StreamedResponse(body.stream, 200, headers: _streamHeaders)));
    final rendered = await renderer.render(_request());
    final heard = <List<int>>[];
    final result = rendered.track.stream!.listen(heard.add).asFuture<void>();
    final failed = expectLater(result, throwsStateError);
    body.add([1, 2]);
    body.addError(StateError('Provider disconnected.'));
    await failed;
    expect(heard, [[1, 2]]);
    unawaited(body.close());
    renderer.close();
  });

  test('debug rejects stale or unversioned endpoints before consuming audio', () async {
    for (final revision in [null, 'narrator-modes-v1']) {
      var canceled = false;
      final body = StreamController<List<int>>(onCancel: () { canceled = true; });
      final renderer = _streamRenderer(MockClient.streaming((_, _) async =>
          http.StreamedResponse(body.stream, 200, headers: {
            if (revision != null) 'x-narration-revision': revision,
          })));
      await expectLater(renderer.render(_request()), throwsStateError);
      expect(canceled, isTrue);
      unawaited(body.close());
      renderer.close();
    }
  });

  test('fetches opening credits without a camera or client-side credential', () async {
    late Map<String, dynamic> payload;
    final renderer = NetlifyNarrationRenderer(
      endpoint: Uri.parse('https://example.test/api/narrate'),
      voice: OpenRouterVoiceOption.jade,
      language: NarrationLanguage.french,
      characterName: 'Ari',
      client: _currentClient((request) async {
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
      'voice': 'jade',
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
      client: _currentClient((request) async {
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
    expect(payload['story']['currentActivity'], '');
    expect(payload['story']['openThread'], '');
    expect(payload['story']['recentNarrations'], ['Els dits reposen sobre el teclat.']);
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
    expect(await http.ByteStream(rendered.track.stream!).toBytes(), <int>[0x49, 0x44, 0x33]);
    renderer.close();
  });

  test('synthesizes startup speech through the server endpoint', () async {
    late Map<String, dynamic> payload;
    final renderer = NetlifyNarrationRenderer(
      endpoint: Uri.parse('https://example.test/api/narrate'),
      voice: OpenRouterVoiceOption.davidAttenborough,
      language: NarrationLanguage.italian,
      characterName: 'Ari',
      client: _currentClient((request) async {
        payload = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response.bytes(<int>[0x49, 0x44, 0x33], 200);
      }),
    );

    final track = await renderer.synthesize('È giunto il momento.');

    expect(payload['kind'], 'speech');
    expect(payload['voice'], 'david-attenborough');
    expect(payload['language'], 'it');
    expect(await http.ByteStream(track.stream!).toBytes(), <int>[0x49, 0x44, 0x33]);
    renderer.close();
  });

  test('keeps a long opening out of bounded activity and thread fields', () async {
    late Map<String, dynamic> payload;
    final renderer = NetlifyNarrationRenderer(
      endpoint: Uri.parse('https://example.test/api/narrate'),
      voice: OpenRouterVoiceOption.morganFreeman,
      language: NarrationLanguage.english,
      characterName: 'Ari',
      client: _currentClient((request) async {
        payload = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response.bytes([0x49, 0x44, 0x33], 200, headers: {
          'x-narration-text': base64Url.encode(utf8.encode('The memory continued.')),
          'x-narration-revision': NetlifyNarrationRenderer.revision,
        });
      }),
    );
    final original = _request();
    final opening = 'A remembered detail. ' * 25;
    await renderer.render(NarrationRequest(
      prompt: original.prompt,
      observation: original.observation,
      captures: original.captures,
      memory: NarrativeMemorySnapshot(recentNarrations: [
        NarrationMemoryEntry(text: opening, observedAt: DateTime.utc(2026)),
      ]),
    ));
    expect(payload['story']['recentNarrations'], [opening]);
    expect(payload['story']['currentActivity'], '');
    expect(payload['story']['openThread'], '');
    renderer.close();
  });

  test('empty returned state retires resolved activity and motifs', () async {
    final renderer = NetlifyNarrationRenderer(
      endpoint: Uri.parse('https://example.test/api/narrate'),
      voice: OpenRouterVoiceOption.jade,
      language: NarrationLanguage.english,
      characterName: 'Ari',
      client: _currentClient(
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
      client: _currentClient(
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
      client: _currentClient(
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

final _streamHeaders = <String, String>{
  'x-narration-revision': NetlifyNarrationRenderer.revision,
  'x-narration-text': base64Url.encode(utf8.encode('The memory continued.')),
};

NetlifyNarrationRenderer _streamRenderer(http.Client client) =>
    NetlifyNarrationRenderer(
      endpoint: Uri.parse('http://localhost:8888/api/narrate'),
      voice: OpenRouterVoiceOption.morganFreeman,
      language: NarrationLanguage.english,
      characterName: 'Ari',
      client: client,
    );

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

MockClient _currentClient(MockClientHandler handler) => MockClient((request) async {
  final response = await handler(request);
  return http.Response.bytes(response.bodyBytes, response.statusCode, headers: {
    ...response.headers,
    'x-narration-revision': NetlifyNarrationRenderer.revision,
  });
});
