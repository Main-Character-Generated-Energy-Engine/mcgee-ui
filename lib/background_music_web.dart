import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'background_music.dart';

BackgroundMusic createBackgroundMusic() => _WebBackgroundMusic();

/// Defined in web/background_music.js.
@JS('McGeeMusic')
external _Music? get _music;

extension type _Music._(JSObject _) implements JSObject {
  external void unlock();
  external void load(String url);
  external void play();
  external void duck(bool ducked);
  external void stop();
  external void release();
}

final class _WebBackgroundMusic implements BackgroundMusic {
  @override
  void unlock() => _music?.unlock();

  @override
  void load(String assetKey) =>
      _music?.load(ui_web.assetManager.getAssetUrl(assetKey));

  @override
  void play() => _music?.play();

  @override
  void duck(bool ducked) => _music?.duck(ducked);

  @override
  void stop() => _music?.stop();

  @override
  Future<void> dispose() async => _music?.release();
}
