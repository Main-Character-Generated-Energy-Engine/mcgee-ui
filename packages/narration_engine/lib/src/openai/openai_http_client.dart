// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

abstract interface class OpenAiApi {
  Future<Map<String, Object?>> createResponse(Map<String, Object?> body);

  Future<Uint8List> createSpeech(Map<String, Object?> body);
}

/// Optional Responses API capability for clients that support SSE streaming.
///
/// Each item is one decoded `data:` event. SSE comments and the terminal
/// `[DONE]` marker are consumed by the client and are not emitted.
abstract interface class StreamingOpenAiApi implements OpenAiApi {
  Stream<Map<String, Object?>> createResponseStream(Map<String, Object?> body);
}

/// Minimal OpenAI HTTP client for the MVP. It deliberately has no SDK dependency.
final class OpenAiHttpClient implements StreamingOpenAiApi {
  OpenAiHttpClient({
    required String apiKey,
    http.Client? httpClient,
    Uri? baseUri,
    this.providerName = 'OpenAI',
  }) : _apiKey = apiKey,
       _httpClient = httpClient ?? http.Client(),
       _baseUri = baseUri ?? Uri.parse('https://api.openai.com/v1/');

  final String _apiKey;
  final http.Client _httpClient;
  final Uri _baseUri;
  final String providerName;

  @override
  Future<Map<String, Object?>> createResponse(Map<String, Object?> body) async {
    final bytes = await _postJson('responses', body);
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, Object?>) {
      throw const FormatException(
        'OpenAI Responses API returned non-object JSON',
      );
    }
    return decoded;
  }

  @override
  Stream<Map<String, Object?>> createResponseStream(
    Map<String, Object?> body,
  ) async* {
    final uri = _baseUri.resolve('responses');
    final request = http.Request('POST', uri)
      ..headers.addAll(<String, String>{
        'Authorization': 'Bearer $_apiKey',
        'Accept': 'text/event-stream',
        'Content-Type': 'application/json',
      })
      ..body = jsonEncode({...body, 'stream': true});
    final response = await _httpClient.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final bytes = await response.stream.toBytes();
      throw _requestFailure(
        path: 'responses',
        statusCode: response.statusCode,
        bytes: bytes,
        uri: uri,
      );
    }

    final dataLines = <String>[];
    await for (final line
        in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (line.isEmpty) {
        final event = _decodeServerSentEvent(dataLines);
        dataLines.clear();
        if (event == null) continue;
        if (event == _doneEvent) return;
        yield event as Map<String, Object?>;
        continue;
      }
      if (line.startsWith(':')) continue;

      final colon = line.indexOf(':');
      final field = colon < 0 ? line : line.substring(0, colon);
      if (field != 'data') continue;
      var value = colon < 0 ? '' : line.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);
      dataLines.add(value);
    }

    final event = _decodeServerSentEvent(dataLines);
    if (event != null && event != _doneEvent) {
      yield event as Map<String, Object?>;
    }
  }

  @override
  Future<Uint8List> createSpeech(Map<String, Object?> body) {
    return _postJson('audio/speech', body);
  }

  Future<Uint8List> _postJson(String path, Map<String, Object?> body) async {
    final uri = _baseUri.resolve(path);
    final response = await _httpClient.post(
      uri,
      headers: <String, String>{
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    final bytes = response.bodyBytes;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _requestFailure(
        path: path,
        statusCode: response.statusCode,
        bytes: bytes,
        uri: uri,
      );
    }
    return bytes;
  }

  http.ClientException _requestFailure({
    required String path,
    required int statusCode,
    required List<int> bytes,
    required Uri uri,
  }) {
    final responseText = utf8.decode(bytes, allowMalformed: true);
    final safeMessage = responseText.length <= 2000
        ? responseText
        : '${responseText.substring(0, 2000)}…';
    return http.ClientException(
      '$providerName request to $path failed with HTTP $statusCode: '
      '$safeMessage',
      uri,
    );
  }

  void close() => _httpClient.close();
}

const Object _doneEvent = _DoneEvent();

final class _DoneEvent {
  const _DoneEvent();
}

Object? _decodeServerSentEvent(List<String> dataLines) {
  if (dataLines.isEmpty) return null;
  final data = dataLines.join('\n');
  if (data == '[DONE]') return _doneEvent;
  final decoded = jsonDecode(data);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException(
      'Responses API stream returned a non-object SSE event',
    );
  }
  return decoded;
}
