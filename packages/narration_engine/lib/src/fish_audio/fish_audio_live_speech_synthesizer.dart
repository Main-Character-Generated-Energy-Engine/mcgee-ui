import 'dart:async';
import 'dart:typed_data';

import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;

import '../core/contracts.dart';
import '../core/models.dart';
import 'fish_audio_web_socket_transport.dart';

/// Direct, bidirectional Fish Audio TTS over its MessagePack WebSocket API.
///
/// [synthesize] provides compatibility with [SpeechSynthesizer] by collecting
/// the entire MP3. For lower perceived latency, call [openSession], feed it
/// text as the language model produces complete words or phrases, and consume
/// [FishAudioLiveSession.audioChunks] before [FishAudioLiveSession.completed]
/// settles.
final class FishAudioLiveSpeechSynthesizer
    implements StreamingSpeechSynthesizer {
  FishAudioLiveSpeechSynthesizer({
    required String apiKey,
    required this.transport,
    this.model = 's2.1-pro',
    this.voice = '3ad4d432023c47ee9e6c7805b973630a',
    this.latency = FishAudioLatency.low,
    this.chunkLength = 100,
    this.flushAfterCharacters,
    Uri? baseUri,
  }) : _apiKey = _validateApiKey(apiKey),
       baseUri = baseUri ?? Uri.parse('wss://api.fish.audio/v1/tts/live') {
    if (chunkLength < 100 || chunkLength > 300) {
      throw RangeError.range(chunkLength, 100, 300, 'chunkLength');
    }
    if (voice.trim().isEmpty) {
      throw ArgumentError.value(voice, 'voice', 'Must not be empty.');
    }
    if (model.trim().isEmpty) {
      throw ArgumentError.value(model, 'model', 'Must not be empty.');
    }
    if (flushAfterCharacters case final threshold? when threshold < 1) {
      throw RangeError.range(threshold, 1, null, 'flushAfterCharacters');
    }
  }

  final String _apiKey;
  final FishAudioWebSocketTransport transport;
  final String model;
  final String voice;
  final FishAudioLatency latency;
  final int chunkLength;

  /// Forces an early synthesis pass at a word boundary once this much streamed
  /// text is buffered. This overlaps short LLM responses with Fish generation
  /// even though Fish's normal automatic buffer starts at 100 characters.
  final int? flushAfterCharacters;
  final Uri baseUri;

  /// Opens a session immediately and sends Fish Audio's required start event.
  ///
  /// The caller owns text chunking. Calling [FishAudioLiveSession.flush] after
  /// a complete phrase asks Fish Audio to begin generating it immediately;
  /// calling it for every token may reduce speech quality.
  Future<FishAudioLiveSession> openSession() async {
    final FishAudioWebSocket socket;
    try {
      socket = await transport.connect(
        baseUri,
        headers: <String, String>{
          'Authorization': 'Bearer $_apiKey',
          'model': model,
        },
      );
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        FishAudioException(
          FishAudioFailureKind.connection,
          'Could not open a direct Fish Audio TTS session. The API key, '
          'billing balance, network, or selected model may be unavailable.',
          cause: error,
        ),
        stackTrace,
      );
    }
    return FishAudioLiveSession._(
      socket: socket,
      voice: voice,
      latency: latency,
      chunkLength: chunkLength,
    );
  }

  /// Starts a live session and pipes incremental language-model text into it.
  ///
  /// Set [flushEachChunk] only when each item is a complete phrase. Otherwise
  /// the final flush occurs when [textChunks] closes.
  @override
  Future<FishAudioLiveSession> synthesizeStream(
    Stream<String> textChunks, {
    bool flushEachChunk = false,
  }) async {
    final session = await openSession();
    unawaited(
      session._pipeText(
        textChunks,
        flushEachChunk: flushEachChunk,
        flushAfterCharacters: flushAfterCharacters,
      ),
    );
    return session;
  }

  /// Backwards-compatible provider-specific alias for [synthesizeStream].
  Future<FishAudioLiveSession> synthesizeTextStream(
    Stream<String> textChunks, {
    bool flushEachChunk = false,
  }) {
    return synthesizeStream(textChunks, flushEachChunk: flushEachChunk);
  }

  @override
  Future<AudioTrack> synthesize(String text) async {
    if (text.trim().isEmpty) {
      throw ArgumentError.value(text, 'text', 'Speech text must not be empty');
    }
    final session = await openSession();
    session
      ..addText(text)
      ..finishInput();
    return session.completed;
  }

  static String _validateApiKey(String value) {
    final key = value.trim();
    if (key.isEmpty) {
      throw ArgumentError.value(value, 'apiKey', 'Must not be empty.');
    }
    if (key.contains(RegExp(r'\s'))) {
      throw ArgumentError.value(
        value,
        'apiKey',
        'Must not contain whitespace.',
      );
    }
    return key;
  }
}

enum FishAudioLatency {
  low('low'),
  balanced('balanced'),
  normal('normal');

  const FishAudioLatency(this.apiValue);

  final String apiValue;
}

enum FishAudioFailureKind {
  connection,
  protocol,
  provider,
  emptyAudio,
  cancelled,
}

/// A safe, typed failure that callers can use to fall back to another TTS
/// provider without parsing exception messages.
final class FishAudioException implements Exception {
  const FishAudioException(this.kind, this.message, {this.cause});

  final FishAudioFailureKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() => 'FishAudioException(${kind.name}): $message';
}

/// A connected Fish Audio TTS session.
///
/// Audio is delivered on [audioChunks] as soon as Fish Audio generates it.
/// [completed] additionally collects those chunks into an [AudioTrack] for
/// existing non-streaming playback code.
final class FishAudioLiveSession implements StreamingSpeechSynthesis {
  FishAudioLiveSession._({
    required FishAudioWebSocket socket,
    required String voice,
    required FishAudioLatency latency,
    required int chunkLength,
  }) : _socket = socket {
    _subscription = socket.messages.listen(
      _receive,
      onError: _fail,
      onDone: _socketClosed,
      cancelOnError: false,
    );
    _send(<String, Object?>{
      'event': 'start',
      'request': <String, Object?>{
        'text': '',
        'format': 'mp3',
        'chunk_length': chunkLength,
        'reference_id': voice,
        'latency': latency.apiValue,
      },
    });
  }

  final FishAudioWebSocket _socket;
  final StreamController<Uint8List> _audioController =
      StreamController<Uint8List>.broadcast(sync: true);
  final Completer<AudioTrack> _completed = Completer<AudioTrack>();
  final BytesBuilder _audio = BytesBuilder(copy: false);

  late final StreamSubscription<Uint8List> _subscription;
  bool _inputFinished = false;
  bool _terminal = false;
  bool _sentSpeech = false;

  /// Progressive MP3 chunks. Subscribe immediately after opening the session.
  Stream<Uint8List> get audioChunks => _audioController.stream;

  /// The concatenated MP3 after the server sends `finish` with reason `stop`.
  @override
  Future<AudioTrack> get completed => _completed.future;

  void addText(String text) {
    _ensureInputOpen();
    if (text.isEmpty) {
      return;
    }
    _sentSpeech = _sentSpeech || text.trim().isNotEmpty;
    _send(<String, Object?>{'event': 'text', 'text': text});
  }

  /// Forces Fish Audio to synthesize all text buffered so far.
  void flush() {
    _ensureInputOpen();
    _send(const <String, Object?>{'event': 'flush'});
  }

  /// Flushes buffered text and closes the input side of the session.
  ///
  /// Generated audio can continue arriving until [completed] settles.
  void finishInput() {
    _ensureInputOpen();
    if (!_sentSpeech) {
      _fail(ArgumentError.value('', 'text', 'Speech text must not be empty'));
      return;
    }
    flush();
    _send(const <String, Object?>{'event': 'stop'});
    _inputFinished = true;
  }

  /// Stops receiving output and closes the connection.
  @override
  Future<void> cancel() async {
    if (!_terminal) {
      _fail(
        const FishAudioException(
          FishAudioFailureKind.cancelled,
          'Fish Audio synthesis was cancelled.',
        ),
      );
    }
    await _socket.close();
  }

  Future<void> _pipeText(
    Stream<String> textChunks, {
    required bool flushEachChunk,
    required int? flushAfterCharacters,
  }) async {
    var pending = '';
    try {
      await for (final chunk in textChunks) {
        // Keep draining the narrator stream after a provider-side failure so
        // callers can reconstruct the full line for a fallback synthesizer.
        if (_terminal) continue;
        if (flushEachChunk) {
          addText(chunk);
          if (chunk.trim().isNotEmpty) flush();
          continue;
        }
        final threshold = flushAfterCharacters;
        if (threshold == null) {
          addText(chunk);
          continue;
        }
        pending += chunk;
        final boundary = _flushBoundary(pending, threshold);
        if (boundary != null) {
          addText(pending.substring(0, boundary));
          flush();
          pending = pending.substring(boundary);
        }
      }
      if (!_terminal) {
        if (pending.isNotEmpty) addText(pending);
        finishInput();
      }
    } catch (error, stackTrace) {
      _fail(error, stackTrace);
      await _socket.close();
    }
  }

  static int? _flushBoundary(String text, int threshold) {
    if (text.length < threshold) return null;
    for (var index = threshold - 1; index < text.length; index++) {
      final unit = text.codeUnitAt(index);
      if (unit == 0x20 ||
          unit == 0x09 ||
          unit == 0x0a ||
          unit == 0x2c ||
          unit == 0x2e ||
          unit == 0x3a ||
          unit == 0x3b ||
          unit == 0x21 ||
          unit == 0x3f) {
        return index + 1;
      }
    }
    return null;
  }

  void _receive(Uint8List frame) {
    if (_terminal) {
      return;
    }
    Object? decoded;
    try {
      decoded = msgpack.deserialize(frame, copyBinaryData: true);
    } catch (error, stackTrace) {
      _fail(
        FishAudioException(
          FishAudioFailureKind.protocol,
          'Fish Audio returned an invalid MessagePack frame.',
          cause: error,
        ),
        stackTrace,
      );
      return;
    }
    if (decoded is! Map) {
      _fail(
        const FishAudioException(
          FishAudioFailureKind.protocol,
          'Fish Audio returned a non-object event.',
        ),
      );
      return;
    }

    switch (decoded['event']) {
      case 'audio':
        final value = decoded['audio'];
        final Uint8List chunk;
        if (value is Uint8List) {
          chunk = value;
        } else if (value is List<int>) {
          chunk = Uint8List.fromList(value);
        } else {
          _fail(
            const FishAudioException(
              FishAudioFailureKind.protocol,
              'Fish Audio returned an audio event without binary audio.',
            ),
          );
          return;
        }
        if (chunk.isNotEmpty) {
          _audio.add(chunk);
          _audioController.add(chunk);
        }
      case 'finish':
        if (decoded['reason'] != 'stop') {
          _fail(
            const FishAudioException(
              FishAudioFailureKind.provider,
              'Fish Audio reported that synthesis failed.',
            ),
          );
          return;
        }
        final bytes = _audio.takeBytes();
        if (bytes.isEmpty) {
          _fail(
            const FishAudioException(
              FishAudioFailureKind.emptyAudio,
              'Fish Audio completed synthesis without returning MP3 audio.',
            ),
          );
          return;
        }
        _terminal = true;
        _audioController.close();
        _completed.complete(
          AudioTrack(
            id: 'fish-audio-mp3-${bytes.length}-${DateTime.now().microsecondsSinceEpoch}',
            bytes: bytes,
          ),
        );
        unawaited(_subscription.cancel());
        unawaited(_socket.close());
      default:
        // Ignore unknown events for forward compatibility, per Fish Audio's
        // AsyncAPI contract.
        return;
    }
  }

  void _socketClosed() {
    if (!_terminal) {
      _fail(
        const FishAudioException(
          FishAudioFailureKind.connection,
          'Fish Audio closed the connection before synthesis completed.',
        ),
      );
    }
  }

  void _fail(Object error, [StackTrace? stackTrace]) {
    if (_terminal) {
      return;
    }
    _terminal = true;
    if (!_audioController.isClosed) {
      _audioController.addError(error, stackTrace);
      _audioController.close();
    }
    _completed.completeError(error, stackTrace);
    unawaited(_subscription.cancel());
    unawaited(_socket.close());
  }

  void _send(Map<String, Object?> event) {
    if (_terminal) {
      throw StateError('Fish Audio session has ended.');
    }
    _socket.send(msgpack.serialize(event));
  }

  void _ensureInputOpen() {
    if (_terminal) {
      throw StateError('Fish Audio session has ended.');
    }
    if (_inputFinished) {
      throw StateError('Fish Audio input has already finished.');
    }
  }
}
