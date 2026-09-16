import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
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
  static const revision = 'narration-stream-v2';
  final Set<_AudioResponse> _responses = {};
  final Set<Completer<void>> _requests = {};

  Future<FilmOpening> generateOpening() async {
    final response = await _send(<String, Object?>{
      'kind': 'opening',
      'voice': voice.name,
      'language': language.apiValue,
      'characterName': characterName,
    });
    try {
      final body = await response.response.stream.bytesToString()
          .timeout(const Duration(seconds: 30));
      return FilmOpening.fromJson(jsonDecode(body));
    } finally {
      _abort(response.abort);
    }
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
    final response = await _send(<String, Object?>{
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
        // The opening is already in recentNarrations. It is not a visible
        // activity and may exceed the bounded structured-state fields.
        'currentActivity': request.memory.canon['current_activity'] ?? '',
        'openThread': request.memory.canon['open_thread'] ?? '',
      },
      'capture': <String, Object?>{
        'id': capture.id,
        'capturedAt': capture.capturedAt.toUtc().toIso8601String(),
        'mediaType': _captureMediaType(capture),
        'bytesBase64': base64Encode(capture.bytes!),
        'protagonistHint': ?capture.protagonistHint,
      },
    });
    try {
      final text = _responseText(response.response);
      final storyState = _responseStoryState(response.response);
      return RenderedNarration(
        draft: NarrationDraft.speak(
          text,
          motifs: storyState?.recurringElements ?? const <String>[],
          canonUpdates: storyState?.canonUpdates ?? const <String, String>{},
        ),
        track: _responseTrack(response, capture.id),
      );
    } catch (_) {
      _abort(response.abort);
      await response.response.stream.listen(null).cancel();
      rethrow;
    }
  }

  @override
  Future<AudioTrack> synthesize(String text) async {
    final spokenText = text.trim();
    if (spokenText.isEmpty) {
      throw ArgumentError.value(text, 'text', 'Must not be empty.');
    }
    final response = await _send(<String, Object?>{
      'kind': 'speech',
      'text': spokenText,
      'voice': voice.name,
      'language': language.apiValue,
    });
    return _responseTrack(response, 'startup');
  }

  Future<({http.StreamedResponse response, Completer<void> abort})> _send(
    Map<String, Object?> payload,
  ) async {
    final timeout = payload['kind'] == 'opening'
        ? const Duration(seconds: 30)
        : const Duration(seconds: 18);
    final abort = Completer<void>();
    _requests.add(abort);
    final request = http.AbortableRequest(
      'POST', endpoint, abortTrigger: abort.future,
    )
      ..headers.addAll(const {
        'Content-Type': 'application/json',
        'Accept': 'audio/mpeg, application/json',
      })
      ..body = jsonEncode(payload);
    try {
      final response = await _client.send(request).timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = await response.stream.bytesToString().timeout(timeout);
        throw http.ClientException(
          'Netlify narration failed with HTTP ${response.statusCode}: '
          '${message.length <= 1000 ? message : '${message.substring(0, 1000)}…'}',
          endpoint,
        );
      }
      if (kDebugMode && response.headers['x-narration-revision'] != revision) {
        _abort(abort);
        await response.stream.listen(null).cancel();
        throw StateError(
          '$endpoint is not serving $revision '
          '(received ${response.headers['x-narration-revision'] ?? 'no revision'}). '
          'Restart the local functions server or redeploy the backend. '
          'Debug builds refuse incompatible narration endpoints.',
        );
      }
      return (response: response, abort: abort);
    } catch (_) {
      _abort(abort);
      rethrow;
    }
  }

  AudioTrack _responseTrack(
    ({http.StreamedResponse response, Completer<void> abort}) pending,
    String sourceId,
  ) {
    late final _AudioResponse audio;
    audio = _AudioResponse(pending.response.stream, onClose: () {
      _abort(pending.abort);
      _responses.remove(audio);
    });
    _responses.add(audio);
    return AudioTrack.fromStream(
      id: 'netlify-$sourceId',
      stream: audio.stream,
      onCancel: audio.cancel,
    );
  }

  String _responseText(http.BaseResponse response) {
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

  _StoryState? _responseStoryState(http.BaseResponse response) {
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

  void _abort(Completer<void> abort) {
    _requests.remove(abort);
    if (!abort.isCompleted) abort.complete();
  }

  void cancelPending() {
    for (final abort in _requests.toList()) {
      _abort(abort);
    }
    for (final response in _responses.toList()) {
      unawaited(response.cancel());
    }
  }

  void close() {
    cancelPending();
    _client.close();
  }
}

// Read immediately while a track waits its turn in the engine's audio queue.
// Errors are retained in the single-subscription stream until playback listens.
final class _AudioResponse {
  _AudioResponse(Stream<List<int>> source, {required this.onClose}) {
    _controller.onCancel = cancel;
    _subscription = source.timeout(const Duration(seconds: 15)).listen(
      (bytes) {
        if (bytes.isEmpty || _closed) return;
        _byteCount += bytes.length;
        if (_byteCount > 8 * 1024 * 1024) {
          _fail(StateError('Narration audio exceeded the size limit.'));
          return;
        }
        _controller.add(bytes);
      },
      onError: (Object error, StackTrace stack) => _fail(error, stack),
      onDone: () {
        if (_closed) return;
        if (_byteCount == 0) {
          _fail(StateError('Netlify narration returned an empty MP3.'));
        } else {
          _closed = true;
          unawaited(_controller.close());
          onClose();
        }
      },
    );
  }

  final void Function() onClose;
  final _controller = StreamController<List<int>>();
  StreamSubscription<List<int>>? _subscription;
  bool _closed = false;
  int _byteCount = 0;
  Stream<List<int>> get stream => _controller.stream;

  void _fail(Object error, [StackTrace? stack]) {
    if (_closed) return;
    _controller.addError(error, stack);
    unawaited(cancel());
  }

  Future<void> cancel() async {
    if (_closed) return;
    _closed = true;
    onClose();
    await _subscription?.cancel();
    unawaited(_controller.close());
  }
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
