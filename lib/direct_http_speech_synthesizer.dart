import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:http/http.dart' as http;
import 'package:mcgee/narration_engine.dart';
import 'package:mcgee/openrouter.dart';

const speechStartupTimeout = Duration(seconds: 10);

/// Browser-compatible, streaming Fish Audio HTTP TTS.
final class DirectHttpSpeechSynthesizer implements SpeechSynthesizer {
  DirectHttpSpeechSynthesizer({
    required this.fishApiKey,
    required this.voice,
    Uri? endpoint,
    http.Client? client,
    this.startupTimeout = speechStartupTimeout,
  }) : endpoint = endpoint ?? Uri.parse('https://api.fish.audio/v1/tts'),
       _client = client ?? http.Client();

  final String fishApiKey;
  final Uri endpoint;
  final http.Client _client;
  final Duration startupTimeout;
  OpenRouterVoiceOption voice;
  final Set<_PendingAudio> _active = {};
  final Set<Completer<void>> _requests = {};

  @override
  Future<AudioTrack> synthesize(String text) async {
    final spoken = text.trim();
    if (spoken.isEmpty) {
      throw ArgumentError.value(text, 'text', 'Must not be empty.');
    }
    return _send(
      endpoint: endpoint,
      key: fishApiKey,
      headers: fishApiKey.isEmpty ? const {} : {'model': voice.model},
      body: {
        'text': spoken,
        'reference_id': voice.voiceId,
        'format': 'mp3',
        'latency': 'low',
        'chunk_length': 100,
      },
      source: 'fish',
    );
  }

  Future<AudioTrack> _send({
    required Uri endpoint,
    required String key,
    required Map<String, String> headers,
    required Map<String, Object?> body,
    required String source,
  }) async {
    final started = Stopwatch()..start();
    Duration remainingStartup() {
      final left = startupTimeout - started.elapsed;
      return left > Duration.zero ? left : Duration.zero;
    }

    final abort = Completer<void>();
    _requests.add(abort);
    final request =
        http.AbortableRequest('POST', endpoint, abortTrigger: abort.future)
          ..headers.addAll({
            if (key.isNotEmpty) 'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
            ...headers,
          })
          ..body = jsonEncode(body);
    final http.StreamedResponse response;
    try {
      response = await _client
          .send(request)
          .timeout(
            startupTimeout,
            onTimeout: () => throw TimeoutException(
              'Fish speech response headers missed the startup deadline.',
              startupTimeout,
            ),
          );
    } catch (_) {
      if (!abort.isCompleted) abort.complete();
      _requests.remove(abort);
      rethrow;
    }
    if (response.statusCode != 200) {
      await response.stream.listen(null).cancel();
      if (!abort.isCompleted) abort.complete();
      _requests.remove(abort);
      throw http.ClientException(
        '$source speech failed with HTTP ${response.statusCode}.',
      );
    }
    late final _PendingAudio pending;
    pending = _PendingAudio(
      response.stream,
      timeout: startupTimeout,
      onFirstChunk: () {
        if (kDebugMode) {
          debugPrint(
            '[MCGEE] $source first audio: ${started.elapsedMilliseconds} ms',
          );
        }
      },
      onClose: () {
        if (!abort.isCompleted) abort.complete();
        _requests.remove(abort);
        _active.remove(pending);
      },
    );
    if (!pending.isClosed) _active.add(pending);
    try {
      await pending.firstChunk.future.timeout(
        remainingStartup(),
        onTimeout: () => throw TimeoutException(
          'Fish speech returned no audio bytes before the startup deadline.',
          startupTimeout,
        ),
      );
    } catch (_) {
      await pending.cancel();
      rethrow;
    }
    return AudioTrack.fromStream(
      id: '$source-${DateTime.now().microsecondsSinceEpoch}',
      stream: pending.stream,
      onCancel: pending.cancel,
    );
  }

  Future<void> cancelPending() async {
    for (final abort in _requests.toList()) {
      if (!abort.isCompleted) abort.complete();
    }
    for (final pending in _active.toList()) {
      await pending.cancel();
    }
  }

  void close() {
    for (final abort in _requests.toList()) {
      if (!abort.isCompleted) abort.complete();
    }
    for (final pending in _active.toList()) {
      unawaited(pending.cancel());
    }
    _client.close();
  }
}

final class _PendingAudio {
  _PendingAudio(
    Stream<List<int>> source, {
    required this.timeout,
    required this.onClose,
    required this.onFirstChunk,
  }) {
    _controller.onCancel = cancel;
    _subscription = source
        .timeout(
          timeout,
          onTimeout: (sink) => sink.addError(
            TimeoutException('Fish speech audio stream stalled.', timeout),
          ),
        )
        .listen(
          (bytes) {
            if (_closed || bytes.isEmpty) return;
            if (_byteCount == 0) {
              onFirstChunk();
              firstChunk.complete();
            }
            _byteCount += bytes.length;
            if (_byteCount > 8 * 1024 * 1024) {
              _fail(StateError('Speech audio exceeded the size limit.'));
              return;
            }
            _controller.add(bytes);
          },
          onError: (Object error, StackTrace stack) => _fail(error, stack),
          onDone: () {
            if (_closed) return;
            if (_byteCount == 0) {
              _fail(StateError('Speech returned empty audio.'));
            } else {
              _closed = true;
              unawaited(_controller.close());
              onClose();
            }
          },
        );
  }

  final void Function() onClose;
  final void Function() onFirstChunk;
  final Duration timeout;
  final firstChunk = Completer<void>();
  final _controller = StreamController<List<int>>();
  StreamSubscription<List<int>>? _subscription;
  int _byteCount = 0;
  bool _closed = false;
  bool get isClosed => _closed;
  Stream<List<int>> get stream => _controller.stream;

  void _fail(Object error, [StackTrace? stack]) {
    if (_closed) return;
    if (!firstChunk.isCompleted) firstChunk.completeError(error, stack);
    _controller.addError(error, stack);
    unawaited(cancel());
  }

  Future<void> cancel() async {
    if (_closed) return;
    _closed = true;
    if (!firstChunk.isCompleted) {
      firstChunk.completeError(StateError('Speech was canceled.'));
    }
    onClose();
    await _subscription?.cancel();
    unawaited(_controller.close());
  }
}
