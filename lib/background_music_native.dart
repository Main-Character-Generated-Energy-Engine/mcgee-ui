import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'background_music.dart';

BackgroundMusic createBackgroundMusic() => _NativeBackgroundMusic();

/// Mirrors web/background_music.js with audioplayers and stepped volume fades.
final class _NativeBackgroundMusic implements BackgroundMusic {
  static const _full = 0.32;
  static const _ducked = 0.11;
  static const _fadeStep = Duration(milliseconds: 50);

  AudioPlayer? _player;
  String? _assetKey;
  Timer? _fade;
  double _volume = 0;
  bool _playing = false;
  bool _isDucked = false;

  double get _level => _isDucked ? _ducked : _full;

  @override
  void unlock() {}

  @override
  void load(String assetKey) {
    if (assetKey == _assetKey) return;
    _release();
    // Bundled assets need no prefetch, so the player is created on play().
    _assetKey = assetKey;
  }

  @override
  void play() {
    final assetKey = _assetKey;
    if (assetKey == null || _playing) return;
    _playing = true;
    final player = _player ??= AudioPlayer();
    _guard(() async {
      // Asset keys already include lib/assets/, so skip the default prefix.
      player.audioCache = AudioCache(prefix: '');
      await player.setReleaseMode(ReleaseMode.loop);
      await player.setVolume(_volume);
      await player.play(AssetSource(assetKey), volume: _volume);
    });
    _fadeTo(_level, const Duration(milliseconds: 2500));
  }

  @override
  void duck(bool ducked) {
    _isDucked = ducked;
    if (!_playing) return;
    // Quick dip before speech, slow recovery after it.
    _fadeTo(_level, Duration(milliseconds: ducked ? 350 : 1600));
  }

  @override
  void stop() {
    final player = _player;
    if (player == null || !_playing) return;
    _playing = false;
    _isDucked = false;
    _fadeTo(
      0,
      const Duration(seconds: 2),
      then: () => _guard(() async {
        await player.pause();
        await player.seek(Duration.zero);
      }),
    );
  }

  @override
  Future<void> dispose() async => _release();

  void _release() {
    _fade?.cancel();
    _playing = false;
    _volume = 0;
    final player = _player;
    _player = null;
    _assetKey = null;
    if (player != null) _guard(player.dispose);
  }

  void _fadeTo(double target, Duration duration, {VoidCallback? then}) {
    _fade?.cancel();
    final player = _player;
    if (player == null) return;
    final steps = (duration.inMilliseconds / _fadeStep.inMilliseconds).ceil();
    final start = _volume;
    var step = 0;
    _fade = Timer.periodic(_fadeStep, (timer) {
      step++;
      _volume = start + (target - start) * (step / steps).clamp(0.0, 1.0);
      _guard(() => player.setVolume(_volume));
      if (step >= steps) {
        timer.cancel();
        then?.call();
      }
    });
  }

  /// Music is optional: failures are logged and never interrupt narration.
  void _guard(Future<void> Function() action) {
    unawaited(
      Future.sync(action).catchError((Object error, StackTrace stackTrace) {
        debugPrint('[MCGEE] Background music failed: $error');
      }),
    );
  }
}
