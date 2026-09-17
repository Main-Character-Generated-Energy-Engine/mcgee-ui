/// Direct Fish Audio adapters that are independent of `dart:io`.
///
/// Hosts provide a [FishAudioWebSocketTransport]. Dart IO hosts can use the
/// implementation exported by `fish_audio_io.dart`.
library;

export 'src/fish_audio/fish_audio_live_speech_synthesizer.dart';
export 'src/fish_audio/fish_audio_web_socket_transport.dart';
