// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

abstract interface class OpenAiApi {
  Future<Map<String, Object?>> createResponse(Map<String, Object?> body);

  Future<Uint8List> createSpeech(Map<String, Object?> body);
}

/// Minimal OpenAI HTTP client for the MVP. It deliberately has no SDK dependency.
final class OpenAiHttpClient implements OpenAiApi {
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
      final responseText = utf8.decode(bytes, allowMalformed: true);
      final safeMessage = responseText.length <= 2000
          ? responseText
          : '${responseText.substring(0, 2000)}…';
      throw http.ClientException(
        '$providerName request to $path failed with HTTP ${response.statusCode}: '
        '$safeMessage',
        uri,
      );
    }
    return bytes;
  }

  void close() => _httpClient.close();
}
