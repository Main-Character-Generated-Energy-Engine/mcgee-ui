import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:narration_engine/narration_engine.dart';
import 'package:narration_engine/openrouter.dart';

import 'film_opening.dart';

/// Calls the fused OpenRouter-to-Fish operation hosted as a Netlify Function.
///
/// Provider credentials stay entirely inside the function environment.
final class NetlifyNarrationRenderer
    implements NarrationRenderer, SpeechSynthesizer {
  NetlifyNarrationRenderer({
    required this.endpoint,
    required this.voice,
    required this.language,
    required this.characterName,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final Uri endpoint;
  final http.Client _client;
  OpenRouterVoiceOption voice;
  final NarrationLanguage language;
  final String characterName;

  Future<FilmOpening> generateOpening() async {
    final response = await _post(<String, Object?>{
      'kind': 'opening',
      'language': language.apiValue,
      'characterName': characterName,
    });
    return FilmOpening.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
  }

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
      'characterName': characterName,
      'story': <String, Object?>{
        'summary': request.memory.canon['story_summary'] ??
            request.memory.storySummary,
        'recentNarrations': <String>[
          for (final narration in request.memory.recentNarrations)
            narration.text,
        ],
        'canon': <String, String>{
          for (final entry in request.memory.canon.entries)
            if (!const <String>{
              'story_summary',
              'current_activity',
              'open_thread',
              'recurring_elements',
            }.contains(entry.key))
              entry.key: entry.value,
        },
        'recurringElements': _decodeRecurringElements(
          request.memory.canon['recurring_elements'],
        ),
        'currentActivity': request.memory.canon['current_activity'] ??
            (request.memory.recentNarrations.isEmpty
                ? ''
                : request.memory.recentNarrations.last.text),
        'openThread': request.memory.canon['open_thread'] ??
            (request.memory.recentNarrations.isEmpty
                ? ''
                : request.memory.recentNarrations.last.text),
      },
      'capture': <String, Object?>{
        'id': capture.id,
        'capturedAt': capture.capturedAt.toUtc().toIso8601String(),
        'mediaType': _captureMediaType(capture),
        'bytesBase64': base64Encode(capture.bytes!),
        'protagonistHint': ?capture.protagonistHint,
      },
    });
    final text = _responseText(response);
    final storyState = _responseStoryState(response);
    return RenderedNarration(
      draft: NarrationDraft.speak(
        text,
        motifs: storyState?.recurringElements ?? const <String>[],
        canonUpdates: storyState?.canonUpdates ?? const <String, String>{},
      ),
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
    final timeout = payload['kind'] == 'opening'
        ? const Duration(seconds: 30)
        : const Duration(seconds: 18);
    final response = await _client
        .post(
          endpoint,
          headers: const <String, String>{
            'Content-Type': 'application/json',
            'Accept': 'audio/mpeg, application/json',
          },
          body: jsonEncode(payload),
        )
        .timeout(timeout);
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

  _StoryState? _responseStoryState(http.Response response) {
    final encodedState = response.headers['x-story-state'];
    if (encodedState == null || encodedState.isEmpty) {
      return null;
    }
    try {
      final value = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(encodedState))),
      );
      if (value is! Map) throw const FormatException('Invalid story state.');
      String field(String name, {bool allowEmpty = false}) {
        final text = value[name];
        if (text is! String || (!allowEmpty && text.trim().isEmpty)) {
          throw FormatException('Invalid story state $name.');
        }
        return text.trim();
      }

      final recurring = value['recurringElements'];
      return _StoryState(
        storySummary: field('storySummary'),
        currentActivity: field('currentActivity', allowEmpty: true),
        openThread: field('openThread', allowEmpty: true),
        recurringElements: recurring is List
            ? recurring.whereType<String>().take(8).toList()
            : const <String>[],
      );
    } on Object catch (error) {
      throw FormatException('Netlify narration returned invalid story state.', error);
    }
  }

  void close() => _client.close();
}

final class _StoryState {
  const _StoryState({
    this.storySummary = '',
    this.currentActivity = '',
    this.openThread = '',
    this.recurringElements = const <String>[],
  });

  final String storySummary;
  final String currentActivity;
  final String openThread;
  final List<String> recurringElements;

  Map<String, String> get canonUpdates => <String, String>{
    'story_summary': storySummary,
    'current_activity': currentActivity,
    'open_thread': openThread,
    'recurring_elements': jsonEncode(recurringElements),
  };
}

List<String> _decodeRecurringElements(String? encoded) {
  if (encoded == null || encoded.trim().isEmpty) return const <String>[];
  try {
    final value = jsonDecode(encoded);
    if (value is List) {
      return value.whereType<String>().take(8).toList();
    }
  } on FormatException {
    // Accept the comma-separated form written by pre-state-protocol builds.
  }
  return encoded
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .take(8)
      .toList();
}

String _captureMediaType(CapturedImage capture) {
  final path = capture.path?.toLowerCase() ?? '';
  if (path.endsWith('.png')) return 'image/png';
  if (path.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}
