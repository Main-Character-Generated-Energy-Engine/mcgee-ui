import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mcgee/src/openrouter/openrouter_http_client.dart';
import 'package:test/test.dart';

void main() {
  test('routes response requests to the lowest-latency provider', () async {
    late http.Request sentRequest;
    final client = OpenRouterHttpClient(
      apiKey: 'test-key',
      httpClient: MockClient((request) async {
        sentRequest = request;
        return http.Response('{}', 200);
      }),
    );

    await client.createResponse({'model': 'openai/gpt-5.6-sol'});

    expect(sentRequest.url.path, '/api/v1/responses');
    expect(jsonDecode(sentRequest.body), {
      'model': 'openai/gpt-5.6-sol',
      'provider': {'sort': 'latency'},
    });
  });

  test(
    'preserves other provider preferences while prioritizing latency',
    () async {
      late http.Request sentRequest;
      final client = OpenRouterHttpClient(
        apiKey: 'test-key',
        httpClient: MockClient((request) async {
          sentRequest = request;
          return http.Response('{}', 200);
        }),
      );
      final body = <String, Object?>{
        'model': 'openai/gpt-5.6-sol',
        'provider': <String, Object?>{'allow_fallbacks': true, 'sort': 'price'},
      };

      await client.createResponse(body);

      expect((jsonDecode(sentRequest.body) as Map)['provider'], {
        'allow_fallbacks': true,
        'sort': 'latency',
      });
      expect((body['provider'] as Map)['sort'], 'price');
    },
  );

  test('prioritizes latency for streaming response requests', () async {
    late http.Request sentRequest;
    final client = OpenRouterHttpClient(
      apiKey: 'test-key',
      httpClient: MockClient((request) async {
        sentRequest = request;
        return http.Response(
          'data: {"type":"response.completed"}\n\n',
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }),
    );

    final events = await client.createResponseStream({
      'model': 'openai/gpt-5.6-sol',
    }).toList();

    expect(events, [
      {'type': 'response.completed'},
    ]);
    expect(jsonDecode(sentRequest.body), {
      'model': 'openai/gpt-5.6-sol',
      'provider': {'sort': 'latency'},
      'stream': true,
    });
  });
}
