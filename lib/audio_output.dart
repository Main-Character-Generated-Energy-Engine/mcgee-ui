import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:narration_engine/narration_engine.dart';

/// Flutter playback adapter for MP3 bytes returned by the engine.
final class FlutterAudioOutput implements AudioOutput {
  FlutterAudioOutput({AudioPlayer? player}) : _player = player;

  AudioPlayer? _player;
  StreamSubscription<void>? _completionSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamController<AudioPlaybackProgress>? _activeProgressController;
  Completer<void>? _activeCompletion;
  Duration? _activeDuration;
  bool _disposed = false;

  AudioPlayer get _audioPlayer => _player ??= AudioPlayer();

  @override
  Future<AudioPlayback> play(AudioTrack track) async {
    if (_disposed) {
      throw StateError('The audio output is disposed.');
    }
    await stop();
    _ensureProgressListeners();

    final completion = Completer<void>();
    final progressController =
        StreamController<AudioPlaybackProgress>.broadcast(sync: true);
    _activeCompletion = completion;
    _activeProgressController = progressController;
    _activeDuration = track.duration;
    _completionSubscription = _audioPlayer.onPlayerComplete.listen((_) {
      if (identical(_activeCompletion, completion)) {
        _activeCompletion = null;
        final subscription = _completionSubscription;
        _completionSubscription = null;
        unawaited(subscription?.cancel());
        if (identical(_activeProgressController, progressController)) {
          _activeProgressController = null;
          _activeDuration = null;
          unawaited(progressController.close());
        }
      }
      if (!completion.isCompleted) completion.complete();
    });

    final bytes = track.bytes;
    final source = bytes != null
        ? BytesSource(bytes, mimeType: 'audio/mpeg')
        : DeviceFileSource(track.location!);
    try {
      await _audioPlayer.play(source);
    } catch (_) {
      await _completionSubscription?.cancel();
      _completionSubscription = null;
      _activeCompletion = null;
      _activeProgressController = null;
      _activeDuration = null;
      await progressController.close();
      if (!completion.isCompleted) completion.complete();
      rethrow;
    }

    return AudioPlayback(
      startedAt: DateTime.now(),
      completed: completion.future,
      progress: progressController.stream,
    );
  }

  void _ensureProgressListeners() {
    _durationSubscription ??= _audioPlayer.onDurationChanged.listen((duration) {
      _activeDuration = duration;
    });
    _positionSubscription ??= _audioPlayer.onPositionChanged.listen((position) {
      final controller = _activeProgressController;
      if (controller == null || controller.isClosed) return;
      controller.add(
        AudioPlaybackProgress(position: position, duration: _activeDuration),
      );
    });
  }

  @override
  Future<void> stop() async {
    final completion = _activeCompletion;
    _activeCompletion = null;
    final subscription = _completionSubscription;
    _completionSubscription = null;
    final progressController = _activeProgressController;
    _activeProgressController = null;
    _activeDuration = null;
    await _player?.stop();
    await subscription?.cancel();
    await progressController?.close();
    if (completion != null && !completion.isCompleted) completion.complete();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
    await _positionSubscription?.cancel();
    await _durationSubscription?.cancel();
    await _player?.dispose();
    _player = null;
  }
}
