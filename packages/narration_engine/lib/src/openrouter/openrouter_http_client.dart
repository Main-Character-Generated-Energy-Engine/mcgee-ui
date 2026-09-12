import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../openai/openai_http_client.dart';

/// Minimal OpenRouter client using its OpenAI-compatible endpoints.
final class OpenRouterHttpClient implements OpenAiApi {
  OpenRouterHttpClient({
    required String apiKey,
    http.Client? httpClient,
    Uri? baseUri,
  }) : _delegate = OpenAiHttpClient(
         apiKey: apiKey,
         httpClient: httpClient,
         baseUri: baseUri ?? Uri.parse('https://openrouter.ai/api/v1/'),
         providerName: 'OpenRouter',
       );

  final OpenAiHttpClient _delegate;

  @override
  Future<Map<String, Object?>> createResponse(Map<String, Object?> body) {
    return _delegate.createResponse(body);
  }

  @override
  Future<Uint8List> createSpeech(Map<String, Object?> body) {
    return _delegate.createSpeech(body);
  }

  void close() => _delegate.close();
}
