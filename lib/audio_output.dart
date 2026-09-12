import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:narration_engine/narration_engine.dart';

/// Flutter playback adapter for MP3 bytes returned by the engine.
final class FlutterAudioOutput implements AudioOutput {
  FlutterAudioOutput({AudioPlayer? player}) : _player = player ?? AudioPlayer();

  final AudioPlayer _player;
  StreamSubscription<void>? _completionSubscription;
  Completer<void>? _activeCompletion;
  bool _disposed = false;

  @override
  Future<AudioPlayback> play(AudioTrack track) async {
    if (_disposed) {
      throw StateError('The audio output is disposed.');
    }
    await stop();

    final completion = Completer<void>();
    _activeCompletion = completion;
    _completionSubscription = _player.onPlayerComplete.listen((_) {
      if (identical(_activeCompletion, completion)) {
        _activeCompletion = null;
        final subscription = _completionSubscription;
        _completionSubscription = null;
        unawaited(subscription?.cancel());
      }
      if (!completion.isCompleted) completion.complete();
    });

    final bytes = track.bytes;
    final source = bytes != null
        ? BytesSource(bytes, mimeType: 'audio/mpeg')
        : DeviceFileSource(track.location!);
    try {
      await _player.play(source);
    } catch (_) {
      await _completionSubscription?.cancel();
      _completionSubscription = null;
      _activeCompletion = null;
      if (!completion.isCompleted) completion.complete();
      rethrow;
    }

    return AudioPlayback(
      startedAt: DateTime.now(),
      completed: completion.future,
    );
  }

  @override
  Future<void> stop() async {
    final completion = _activeCompletion;
    _activeCompletion = null;
    final subscription = _completionSubscription;
    _completionSubscription = null;
    await _player.stop();
    await subscription?.cancel();
    if (completion != null && !completion.isCompleted) completion.complete();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
    await _player.dispose();
  }
}
