import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:mcgee/narration_engine.dart';

import 'stream_audio_player.dart';

/// Flutter playback adapter for MP3 bytes returned by the engine.
final class FlutterAudioOutput implements AudioOutput {
  FlutterAudioOutput({AudioPlayer? player}) : _player = player;

  AudioPlayer? _player;
  final StreamAudioPlayer? _streamPlayer = createStreamAudioPlayer();
  StreamSubscription<void>? _completionSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<List<int>>? _bufferSubscription;
  Completer<Uint8List>? _bufferCompletion;
  StreamController<AudioPlaybackProgress>? _activeProgressController;
  Completer<void>? _activeCompletion;
  Duration? _activeDuration;
  Future<void> _playerCommand = Future<void>.value();
  int _generation = 0;
  bool _disposed = false;

  AudioPlayer get _audioPlayer => _player ??= AudioPlayer();

  @override
  Future<AudioPlayback> play(AudioTrack track) async {
    if (_disposed) {
      throw StateError('The audio output is disposed.');
    }
    final generation = ++_generation;
    await _stopPlayback();
    _checkCurrent(generation);
    if (track.stream != null && _streamPlayer != null) {
      final playback = await _streamPlayer.play(track);
      _checkCurrent(generation);
      return playback;
    }

    Completer<void>? completion;
    StreamController<AudioPlaybackProgress>? progressController;
    StreamSubscription<void>? completionSubscription;
    try {
      // Native playback needs complete bytes. Keep buffering cancellable so a
      // stopped or replaced request cannot begin playback when its stream ends.
      final stream = track.stream;
      final bytes = stream == null ? track.bytes : await _readStream(stream);
      _checkCurrent(generation);
      final source = bytes != null
          ? BytesSource(bytes, mimeType: 'audio/mpeg')
          : DeviceFileSource(track.location!);
      _ensureProgressListeners();

      final activeCompletion = completion = Completer<void>();
      final activeProgress = progressController =
          StreamController<AudioPlaybackProgress>.broadcast(sync: true);
      _activeCompletion = activeCompletion;
      _activeProgressController = activeProgress;
      _activeDuration = track.duration;
      completionSubscription = _audioPlayer.onPlayerComplete.listen((_) {
        if (identical(_activeCompletion, activeCompletion)) {
          _activeCompletion = null;
          final subscription = _completionSubscription;
          _completionSubscription = null;
          unawaited(subscription?.cancel());
          if (identical(_activeProgressController, activeProgress)) {
            _activeProgressController = null;
            _activeDuration = null;
            unawaited(activeProgress.close());
          }
        }
        if (!activeCompletion.isCompleted) activeCompletion.complete();
      });
      _completionSubscription = completionSubscription;

      await _runPlayerCommand(() async {
        _checkCurrent(generation);
        await _audioPlayer.play(source);
      });
      _checkCurrent(generation);
      return AudioPlayback(
        startedAt: DateTime.now(),
        completed: activeCompletion.future,
        progress: activeProgress.stream,
      );
    } catch (_) {
      // Only release this invocation's resources: another play may already
      // own the adapter by the time an earlier stream or platform call fails.
      if (identical(_completionSubscription, completionSubscription)) {
        _completionSubscription = null;
      }
      if (identical(_activeCompletion, completion)) {
        _activeCompletion = null;
      }
      if (identical(_activeProgressController, progressController)) {
        _activeProgressController = null;
        _activeDuration = null;
      }
      await completionSubscription?.cancel();
      await progressController?.close();
      if (completion != null && !completion.isCompleted) completion.complete();
      rethrow;
    }
  }

  Future<Uint8List> _readStream(Stream<List<int>> stream) async {
    final builder = BytesBuilder(copy: false);
    final completion = Completer<Uint8List>();
    _bufferCompletion = completion;
    StreamSubscription<List<int>>? subscription;
    try {
      subscription = stream.listen(
        builder.add,
        onError: (Object error, StackTrace stackTrace) {
          if (!completion.isCompleted) completion.completeError(error, stackTrace);
        },
        onDone: () {
          if (!completion.isCompleted) completion.complete(builder.takeBytes());
        },
        cancelOnError: true,
      );
      _bufferSubscription = subscription;
      return await completion.future;
    } finally {
      if (identical(_bufferCompletion, completion)) _bufferCompletion = null;
      if (identical(_bufferSubscription, subscription)) _bufferSubscription = null;
      await subscription?.cancel();
    }
  }

  void _checkCurrent(int generation) {
    if (_disposed || generation != _generation) {
      throw StateError('Audio playback was stopped before it started.');
    }
  }

  Future<void> _runPlayerCommand(Future<void> Function() command) {
    final pending = _playerCommand.then((_) => command());
    // Keep the queue usable after a failed command. The caller still receives
    // the original failure through pending.
    _playerCommand = pending.then<void>((_) {}, onError: (Object _) {});
    return pending;
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
  Future<void> stop() {
    _generation += 1;
    return _stopPlayback();
  }

  Future<void> _stopPlayback() async {
    // Detach synchronously, before any await lets a newer play take ownership.
    final completion = _activeCompletion;
    _activeCompletion = null;
    final subscription = _completionSubscription;
    _completionSubscription = null;
    final progressController = _activeProgressController;
    _activeProgressController = null;
    _activeDuration = null;
    final bufferSubscription = _bufferSubscription;
    _bufferSubscription = null;
    final bufferCompletion = _bufferCompletion;
    _bufferCompletion = null;
    if (bufferCompletion != null && !bufferCompletion.isCompleted) {
      bufferCompletion.completeError(StateError('Audio buffering was stopped.'));
    }
    final player = _player;
    try {
      await Future.wait<void>([
        if (_streamPlayer != null) _streamPlayer.stop(),
        if (player != null) _runPlayerCommand(player.stop),
        if (bufferSubscription != null) bufferSubscription.cancel(),
        if (subscription != null) subscription.cancel(),
        if (progressController != null) progressController.close(),
      ]);
    } finally {
      if (completion != null && !completion.isCompleted) completion.complete();
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    await _positionSubscription?.cancel();
    await _durationSubscription?.cancel();
    await _player?.dispose();
    _player = null;
  }
}
