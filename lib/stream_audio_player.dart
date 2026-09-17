import 'package:mcgee/narration_engine.dart';

import 'stream_audio_player_stub.dart'
    if (dart.library.js_interop) 'stream_audio_player_web.dart' as platform;

abstract interface class StreamAudioPlayer {
  Future<AudioPlayback> play(AudioTrack track);
  Future<void> stop();
}

StreamAudioPlayer? createStreamAudioPlayer() => platform.createStreamAudioPlayer();
