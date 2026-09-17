import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:mcgee/narration_engine.dart';

import 'stream_audio_player.dart';

StreamAudioPlayer createStreamAudioPlayer() => _BrowserStreamAudioPlayer();

@JS('McGeeStreamPlayer')
extension type _Player._(JSObject _) implements JSObject {
  external _Player(JSFunction onProgress);
  external JSPromise<JSNumber> start();
  external JSPromise<JSAny?> append(JSUint8Array bytes);
  external JSPromise<JSAny?> finish();
  external JSPromise<JSAny?> get completed;
  external void fail(String message);
  external void stop();
}

final class _BrowserStreamAudioPlayer implements StreamAudioPlayer {
  _Player? _player;
  AudioTrack? _track;
  StreamIterator<List<int>>? _chunks;
  int _generation = 0;

  @override
  Future<AudioPlayback> play(AudioTrack track) async {
    final stopping = stop();
    final generation = _generation;
    await stopping;
    if (generation != _generation) {
      throw StateError('Narration playback was stopped.');
    }
    final stream = track.stream;
    if (stream == null) throw ArgumentError('Expected streaming audio.');
    final progress = StreamController<AudioPlaybackProgress>.broadcast();
    final player = _Player(
      ((JSNumber position, JSNumber duration) {
        if (progress.isClosed) return;
        final seconds = duration.toDartDouble;
        progress.add(
          AudioPlaybackProgress(
            position: Duration(
              milliseconds: (position.toDartDouble * 1000).round(),
            ),
            duration: seconds < 0
                ? null
                : Duration(milliseconds: (seconds * 1000).round()),
          ),
        );
      }).toJS,
    );
    _player = player;
    _track = track;
    final chunks = StreamIterator(stream);
    _chunks = chunks;
    final started = player.start().toDart;
    final completed = player.completed.toDart.then<void>((_) {}).whenComplete(
      () async {
        await chunks.cancel();
        await track.dispose();
        await progress.close();
        if (identical(_player, player)) {
          _player = null;
          _track = null;
          _chunks = null;
        }
      },
    );
    // An error can arrive before the engine receives its playback handle.
    unawaited(
      completed.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
    unawaited(_feed(player, chunks));
    try {
      final milliseconds = await started;
      return AudioPlayback(
        startedAt: DateTime.fromMillisecondsSinceEpoch(milliseconds.toDartInt),
        completed: completed,
        progress: progress.stream,
      );
    } catch (_) {
      player.stop();
      await chunks.cancel();
      await track.dispose();
      rethrow;
    }
  }

  Future<void> _feed(_Player player, StreamIterator<List<int>> chunks) async {
    try {
      while (await chunks.moveNext()) {
        await player.append(Uint8List.fromList(chunks.current).toJS).toDart;
      }
      await player.finish().toDart;
    } catch (error) {
      player.fail(error.toString());
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    final player = _player;
    final track = _track;
    final chunks = _chunks;
    _player = null;
    _track = null;
    _chunks = null;
    player?.stop();
    await chunks?.cancel();
    await track?.dispose();
  }
}
