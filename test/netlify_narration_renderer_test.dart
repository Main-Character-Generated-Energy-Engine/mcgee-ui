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
      client: MockClient((request) async {
        expect(request.headers.containsKey('Authorization'), isFalse);
        payload = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response.bytes(utf8.encode(jsonEncode({
          'title': 'Le poids des petites choses',
          'director': 'Bastien Valcour de Sève',
          'narration': 'Une vie ordinaire mérite une attention extraordinaire.',
        })), 200);
      }),
    );

    final opening = await renderer.generateOpening();
    expect(payload, {'kind': 'opening', 'language': 'fr'});
    expect(opening.director, 'Bastien Valcour de Sève');
    renderer.close();
  });

  test('returns the spoken text and MP3 from the fused endpoint', () async {
    late http.Request sent;
    final renderer = NetlifyNarrationRenderer(
      endpoint: Uri.parse('https://example.test/api/narrate'),
      voice: OpenRouterVoiceOption.morganFreeman,
      language: NarrationLanguage.catalan,
      client: MockClient((request) async {
        sent = request;
        return http.Response.bytes(
          <int>[0x49, 0x44, 0x33],
          200,
          headers: <String, String>{
            'content-type': 'audio/mpeg',
            'x-narration-text': base64Url.encode(
              utf8.encode(
                'He considers the keyboard, then delegates the matter.',
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
    expect(payload['prompt'], contains('Els dits reposen sobre el teclat.'));
    expect(payload['prompt'], contains('Last spoken line'));
    expect(payload['capture']['bytesBase64'], base64Encode(<int>[1, 2, 3]));
    expect(
      rendered.draft.text,
      'He considers the keyboard, then delegates the matter.',
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

  test('surfaces endpoint failures', () async {
    final renderer = NetlifyNarrationRenderer(
      endpoint: Uri.parse('https://example.test/api/narrate'),
      voice: OpenRouterVoiceOption.morganFreeman,
      language: NarrationLanguage.english,
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
