import 'background_music_native.dart'
    if (dart.library.js_interop) 'background_music_web.dart'
    as platform;

/// One looping track per session: it fades in under the opening credits,
/// dips while the narrator speaks, and fades out when the session ends.
abstract interface class BackgroundMusic {
  /// Call synchronously from a user gesture so browsers allow playback later.
  void unlock();

  /// Starts fetching [assetKey] so it is ready before the credits roll.
  void load(String assetKey);

  void play();
  void duck(bool ducked);
  void stop();
  Future<void> dispose();
}

BackgroundMusic createBackgroundMusic() => platform.createBackgroundMusic();
