import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:narration_engine/narration_engine.dart';
import 'package:narration_engine/openrouter.dart';

/// Calls the fused OpenRouter-to-Fish operation hosted as a Netlify Function.
///
/// Provider credentials stay entirely inside the function environment.
final class NetlifyNarrationRenderer
    implements NarrationRenderer, SpeechSynthesizer {
  NetlifyNarrationRenderer({
    required this.endpoint,
    required this.voice,
    required this.language,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final Uri endpoint;
  final http.Client _client;
  OpenRouterVoiceOption voice;
  final NarrationLanguage language;

  @override
  Future<RenderedNarration> render(NarrationRequest request) async {
    if (request.captures.length != 1 || request.captures.single.bytes == null) {
      throw ArgumentError.value(
        request.captures,
        'request.captures',
        'The Netlify live endpoint requires exactly one in-memory capture.',
      );
    }
    final capture = request.captures.single;
    final response = await _post(<String, Object?>{
      'kind': 'narration',
      'prompt': request.prompt,
      'voice': voice.name,
      'language': language.apiValue,
      'capture': <String, Object?>{
        'id': capture.id,
        'capturedAt': capture.capturedAt.toUtc().toIso8601String(),
        'mediaType': _captureMediaType(capture),
        'bytesBase64': base64Encode(capture.bytes!),
        'protagonistHint': ?capture.protagonistHint,
      },
    });
    final text = _responseText(response);
    return RenderedNarration(
      draft: NarrationDraft.speak(text),
      track: _responseTrack(response, capture.id),
    );
  }

  @override
  Future<AudioTrack> synthesize(String text) async {
    final spokenText = text.trim();
    if (spokenText.isEmpty) {
      throw ArgumentError.value(text, 'text', 'Must not be empty.');
    }
    final response = await _post(<String, Object?>{
      'kind': 'speech',
      'text': spokenText,
      'voice': voice.name,
      'language': language.apiValue,
    });
    return _responseTrack(response, 'startup');
  }

  Future<http.Response> _post(Map<String, Object?> payload) async {
    final response = await _client
        .post(
          endpoint,
          headers: const <String, String>{
            'Content-Type': 'application/json',
            'Accept': 'audio/mpeg',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 18));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = utf8.decode(response.bodyBytes, allowMalformed: true);
      throw http.ClientException(
        'Netlify narration failed with HTTP ${response.statusCode}: '
        '${message.length <= 1000 ? message : '${message.substring(0, 1000)}…'}',
        endpoint,
      );
    }
    return response;
  }

  AudioTrack _responseTrack(http.Response response, String sourceId) {
    if (response.bodyBytes.isEmpty) {
      throw StateError('Netlify narration returned an empty MP3.');
    }
    return AudioTrack.fromBytes(
      id: 'netlify-$sourceId-${response.bodyBytes.length}',
      bytes: Uint8List.fromList(response.bodyBytes),
    );
  }

  String _responseText(http.Response response) {
    final encodedText = response.headers['x-narration-text'];
    if (encodedText == null || encodedText.isEmpty) {
      throw const FormatException(
        'Netlify narration response omitted its spoken text.',
      );
    }
    final text = utf8
        .decode(base64Url.decode(base64Url.normalize(encodedText)))
        .trim();
    if (text.isEmpty) {
      throw const FormatException('Netlify narration text was empty.');
    }
    return text;
  }

  void close() => _client.close();
}

String _captureMediaType(CapturedImage capture) {
  final path = capture.path?.toLowerCase() ?? '';
  if (path.endsWith('.png')) return 'image/png';
  if (path.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}
