import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mcgee/direct_http_speech_synthesizer.dart';
import 'package:mcgee/openrouter.dart';

void main() {
  test('speech startup times out instead of waiting silently', () async {
    final speech = DirectHttpSpeechSynthesizer(
      fishApiKey: '',
      endpoint: Uri.parse('http://localhost:8767/api/speech'),
      voice: OpenRouterVoiceOption.morganFreeman,
      startupTimeout: const Duration(milliseconds: 20),
      client: MockClient.streaming((request, body) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return http.StreamedResponse(Stream.value([1, 2, 3]), 200);
      }),
    );
    expect(speechStartupTimeout, const Duration(seconds: 10));
    await expectLater(
      speech.synthesize('Ari opens the door.'),
      throwsA(
        isA<TimeoutException>().having(
          (error) => error.message,
          'message',
          contains('response headers'),
        ),
      ),
    );
    speech.close();
  });

  test('an HTTP 200 with no audio bytes also times out', () async {
    final audio = StreamController<List<int>>();
    final speech = DirectHttpSpeechSynthesizer(
      fishApiKey: '',
      endpoint: Uri.parse('http://localhost:8767/api/speech'),
      voice: OpenRouterVoiceOption.morganFreeman,
      startupTimeout: const Duration(milliseconds: 20),
      client: MockClient.streaming(
        (request, body) async => http.StreamedResponse(audio.stream, 200),
      ),
    );
    await expectLater(
      speech.synthesize('Ari opens the door.'),
      throwsA(
        isA<TimeoutException>().having(
          (error) => error.message,
          'message',
          contains('no audio bytes'),
        ),
      ),
    );
    speech.close();
    await audio.close();
  });

  test('Fish audio reaches playback before the provider finishes', () async {
    final audio = StreamController<List<int>>();
    final requested = Completer<void>();
    final speech = DirectHttpSpeechSynthesizer(
      fishApiKey: 'fish-test-key',
      voice: OpenRouterVoiceOption.morganFreeman,
      client: MockClient.streaming((request, body) async {
        expect(request.url.toString(), 'https://api.fish.audio/v1/tts');
        expect(request.headers['authorization'], 'Bearer fish-test-key');
        expect(request.headers['model'], 's2.1-pro-free');
        final payload = jsonDecode(await body.bytesToString()) as Map;
        expect(payload['latency'], 'low');
        expect(payload['text'], 'Ari opens the door.');
        requested.complete();
        return http.StreamedResponse(audio.stream, 200);
      }),
    );
    final pending = speech.synthesize('Ari opens the door.');
    await requested.future;
    audio.add([1, 2, 3]);
    final track = await pending;
    final chunks = StreamIterator(track.stream!);
    expect(await chunks.moveNext(), isTrue);
    expect(chunks.current, [1, 2, 3]);
    expect(audio.isClosed, isFalse);
    audio.add([4, 5]);
    unawaited(audio.close());
    expect(await chunks.moveNext(), isTrue);
    expect(chunks.current, [4, 5]);
    expect(await chunks.moveNext(), isFalse);
    await track.dispose();
    speech.close();
  });

  test('Jade uses her Fish voice with s2.1-pro-free', () async {
    final speech = DirectHttpSpeechSynthesizer(
      fishApiKey: 'fish-test-key',
      voice: OpenRouterVoiceOption.jade,
      client: MockClient.streaming((request, body) async {
        expect(request.url.toString(), 'https://api.fish.audio/v1/tts');
        expect(request.headers['model'], 's2.1-pro-free');
        final payload = jsonDecode(await body.bytesToString()) as Map;
        expect(payload['reference_id'], '1e5902ed8ddf433b88a717444bb90510');
        return http.StreamedResponse(Stream.value([1, 2, 3]), 200);
      }),
    );
    final track = await speech.synthesize('The incident continues.');
    expect(await track.stream!.expand((bytes) => bytes).toList(), [1, 2, 3]);
    await track.dispose();
    speech.close();
  });

  test(
    'Fish failure surfaces without requesting another audio provider',
    () async {
      final requests = <Uri>[];
      final speech = DirectHttpSpeechSynthesizer(
        fishApiKey: 'fish-test-key',
        voice: OpenRouterVoiceOption.morganFreeman,
        client: MockClient.streaming((request, _) async {
          requests.add(request.url);
          return http.StreamedResponse(Stream<List<int>>.empty(), 503);
        }),
      );
      await expectLater(
        speech.synthesize('Ari opens the door.'),
        throwsA(isA<http.ClientException>()),
      );
      expect(requests.map((uri) => uri.host), ['api.fish.audio']);
      speech.close();
    },
  );

  test('browser proxy receives no Fish authorization header', () async {
    final speech = DirectHttpSpeechSynthesizer(
      fishApiKey: '',
      endpoint: Uri.parse('http://localhost:8767/api/speech'),
      voice: OpenRouterVoiceOption.morganFreeman,
      client: MockClient.streaming((request, _) async {
        expect(request.url.path, '/api/speech');
        expect(request.headers.containsKey('authorization'), isFalse);
        expect(request.headers.containsKey('model'), isFalse);
        return http.StreamedResponse(Stream.value([1, 2, 3]), 200);
      }),
    );
    final track = await speech.synthesize('Ari opens the door.');
    expect(await track.stream!.expand((bytes) => bytes).toList(), [1, 2, 3]);
    await track.dispose();
    speech.close();
  });
}
