import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:narration_engine/src/openai/openai_http_client.dart';
import 'package:test/test.dart';

void main() {
  test('decodes fragmented Responses API SSE events', () async {
    final transport = _FakeStreamingHttpClient(
      chunks: [
        ': OPENROUTER PROCESS',
        'ING\n\ndata: {"type":"response.output_',
        'text.delta",\ndata: "delta":"Hello"}\n\n',
        'data: {"type":"response.output_text.delta","delta":" world"}\n\n',
        'data: [DONE]\n\n',
      ],
    );
    final client = OpenAiHttpClient(
      apiKey: 'test-key',
      httpClient: transport,
      baseUri: Uri.parse('https://example.test/api/v1/'),
    );

    final events = await client.createResponseStream({
      'model': 'test/model',
      'input': 'hello',
      'stream': false,
    }).toList();

    expect(events, [
      {'type': 'response.output_text.delta', 'delta': 'Hello'},
      {'type': 'response.output_text.delta', 'delta': ' world'},
    ]);
    expect(transport.lastRequest?.url.path, '/api/v1/responses');
    expect(transport.lastRequest?.headers['Accept'], 'text/event-stream');
    expect(transport.lastBody?['stream'], isTrue);
  });

  test('surfaces an HTTP error before an SSE stream starts', () async {
    final client = OpenAiHttpClient(
      apiKey: 'test-key',
      providerName: 'TestRouter',
      httpClient: _FakeStreamingHttpClient(
        statusCode: 429,
        chunks: ['{"error":{"message":"slow down"}}'],
      ),
      baseUri: Uri.parse('https://example.test/api/v1/'),
    );

    await expectLater(
      client.createResponseStream({'input': 'hello'}).toList(),
      throwsA(
        isA<http.ClientException>().having(
          (error) => error.message,
          'message',
          allOf(contains('HTTP 429'), contains('slow down')),
        ),
      ),
    );
  });
}

final class _FakeStreamingHttpClient extends http.BaseClient {
  _FakeStreamingHttpClient({required this.chunks, this.statusCode = 200});

  final List<String> chunks;
  final int statusCode;
  http.BaseRequest? lastRequest;
  Map<String, Object?>? lastBody;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    final requestBytes = await request.finalize().toBytes();
    lastBody = (jsonDecode(utf8.decode(requestBytes)) as Map).map(
      (key, value) => MapEntry(key.toString(), value),
    );
    return http.StreamedResponse(
      Stream<Uint8List>.fromIterable(
        chunks.map((chunk) => Uint8List.fromList(utf8.encode(chunk))),
      ),
      statusCode,
      headers: {'content-type': 'text/event-stream'},
    );
  }
}
