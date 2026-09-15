import 'dart:async';
import 'dart:typed_data';

import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:narration_engine/fish_audio.dart';
import 'package:test/test.dart';

void main() {
  test('starts with authenticated low-latency MP3 configuration', () async {
    final transport = _FakeTransport();
    final synthesizer = FishAudioLiveSpeechSynthesizer(
      apiKey: 'secret-value',
      transport: transport,
    );

    final session = await synthesizer.openSession();

    expect(transport.uri, Uri.parse('wss://api.fish.audio/v1/tts/live'));
    expect(transport.headers, {
      'Authorization': 'Bearer secret-value',
      'model': 's2-pro',
    });
    expect(transport.socket.sent.single, {
      'event': 'start',
      'request': {
        'text': '',
        'format': 'mp3',
        'chunk_length': 100,
        'reference_id': '3ad4d432023c47ee9e6c7805b973630a',
        'latency': 'low',
      },
    });

    final completion = expectLater(
      session.completed,
      throwsA(isA<FishAudioException>()),
    );
    await session.cancel();
    await completion;
  });

  test('SpeechSynthesizer compatibility collects all MP3 chunks', () async {
    final transport = _FakeTransport();
    final synthesizer = FishAudioLiveSpeechSynthesizer(
      apiKey: 'secret-value',
      transport: transport,
    );

    final completed = synthesizer.synthesize('A decisive little entrance.');
    await transport.connected;
    await pumpEventQueue();

    expect(transport.socket.sent.skip(1), [
      {'event': 'text', 'text': 'A decisive little entrance.'},
      {'event': 'flush'},
      {'event': 'stop'},
    ]);

    transport.socket
      ..emit({
        'event': 'audio',
        'audio': Uint8List.fromList([0x49, 0x44]),
      })
      ..emit({'event': 'future-extension', 'value': true})
      ..emit({
        'event': 'audio',
        'audio': Uint8List.fromList([0x33, 0x04]),
      })
      ..emit({'event': 'finish', 'reason': 'stop'});

    final track = await completed;
    expect(track.bytes, [0x49, 0x44, 0x33, 0x04]);
    expect(transport.socket.wasClosed, isTrue);
  });

  test('streams audio before the completed track is available', () async {
    final transport = _FakeTransport();
    final input = StreamController<String>();
    final synthesizer = FishAudioLiveSpeechSynthesizer(
      apiKey: 'secret-value',
      transport: transport,
    );
    final session = await synthesizer.synthesizeTextStream(
      input.stream,
      flushEachChunk: true,
    );
    final received = <List<int>>[];
    final subscription = session.audioChunks.listen(received.add);

    input.add('The hero enters. ');
    await pumpEventQueue();
    expect(transport.socket.sent.skip(1), [
      {'event': 'text', 'text': 'The hero enters. '},
      {'event': 'flush'},
    ]);

    transport.socket.emit({
      'event': 'audio',
      'audio': Uint8List.fromList([1, 2, 3]),
    });
    await pumpEventQueue();
    expect(received, [
      [1, 2, 3],
    ]);

    var completed = false;
    session.completed.then((_) => completed = true);
    expect(completed, isFalse);

    await input.close();
    await pumpEventQueue();
    expect(transport.socket.sent.skip(3), [
      {'event': 'flush'},
      {'event': 'stop'},
    ]);
    transport.socket.emit({'event': 'finish', 'reason': 'stop'});
    expect((await session.completed).bytes, [1, 2, 3]);
    await subscription.cancel();
  });

  test('flushes streamed narration early at a word boundary', () async {
    final transport = _FakeTransport();
    final input = StreamController<String>();
    final synthesizer = FishAudioLiveSpeechSynthesizer(
      apiKey: 'secret-value',
      transport: transport,
      flushAfterCharacters: 24,
    );
    final session = await synthesizer.synthesizeStream(input.stream);

    input.add('The unreasonably confident hero');
    await pumpEventQueue();
    expect(transport.socket.sent.skip(1), [
      {'event': 'text', 'text': 'The unreasonably confident '},
      {'event': 'flush'},
    ]);

    input.add(' enters.');
    await input.close();
    await pumpEventQueue();
    expect(transport.socket.sent.skip(3), [
      {'event': 'text', 'text': 'hero enters.'},
      {'event': 'flush'},
      {'event': 'stop'},
    ]);

    transport.socket
      ..emit({
        'event': 'audio',
        'audio': Uint8List.fromList([1]),
      })
      ..emit({'event': 'finish', 'reason': 'stop'});
    expect((await session.completed).bytes, [1]);
  });

  test('exposes provider failure as a typed fallback signal', () async {
    final transport = _FakeTransport();
    final synthesizer = FishAudioLiveSpeechSynthesizer(
      apiKey: 'secret-value',
      transport: transport,
    );
    final completed = synthesizer.synthesize('A small but billable line.');
    await transport.connected;

    transport.socket.emit({'event': 'finish', 'reason': 'error'});

    await expectLater(
      completed,
      throwsA(
        isA<FishAudioException>().having(
          (error) => error.kind,
          'kind',
          FishAudioFailureKind.provider,
        ),
      ),
    );
  });

  test('rejects an empty text stream and closes its socket', () async {
    final transport = _FakeTransport();
    final synthesizer = FishAudioLiveSpeechSynthesizer(
      apiKey: 'secret-value',
      transport: transport,
    );
    final session = await synthesizer.synthesizeTextStream(
      const Stream<String>.empty(),
    );

    await expectLater(session.completed, throwsArgumentError);
    expect(transport.socket.wasClosed, isTrue);
  });

  test('wraps handshake failure without leaking the API key', () async {
    final transport = _FailingTransport();
    final synthesizer = FishAudioLiveSpeechSynthesizer(
      apiKey: 'do-not-leak-this',
      transport: transport,
    );

    await expectLater(
      synthesizer.openSession(),
      throwsA(
        isA<FishAudioException>()
            .having(
              (error) => error.kind,
              'kind',
              FishAudioFailureKind.connection,
            )
            .having(
              (error) => error.toString(),
              'safe message',
              isNot(contains('do-not-leak-this')),
            ),
      ),
    );
  });
}

final class _FakeTransport implements FishAudioWebSocketTransport {
  final socket = _FakeSocket();
  final _connected = Completer<void>();
  Uri? uri;
  Map<String, String>? headers;

  Future<void> get connected => _connected.future;

  @override
  Future<FishAudioWebSocket> connect(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    this.uri = uri;
    this.headers = headers;
    _connected.complete();
    return socket;
  }
}

final class _FailingTransport implements FishAudioWebSocketTransport {
  @override
  Future<FishAudioWebSocket> connect(
    Uri uri, {
    required Map<String, String> headers,
  }) {
    return Future.error(StateError('Handshake returned HTTP 402'));
  }
}

final class _FakeSocket implements FishAudioWebSocket {
  final _messages = StreamController<Uint8List>();
  final List<Map<Object?, Object?>> sent = [];
  bool wasClosed = false;

  @override
  Stream<Uint8List> get messages => _messages.stream;

  void emit(Map<String, Object?> event) {
    _messages.add(msgpack.serialize(event));
  }

  @override
  void send(Uint8List message) {
    sent.add((msgpack.deserialize(message) as Map).cast<Object?, Object?>());
  }

  @override
  Future<void> close() async {
    wasClosed = true;
    await _messages.close();
  }
}
