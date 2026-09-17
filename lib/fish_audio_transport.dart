import 'package:mcgee/fish_audio.dart';

import 'fish_audio_transport_io.dart'
    if (dart.library.js_interop) 'fish_audio_transport_web.dart'
    as implementation;

FishAudioWebSocketTransport createFishAudioTransport() {
  return implementation.createFishAudioTransport();
}

/// Dart IO sends this credential through Fish's live WebSocket transport.
String fishAudioTransportCredential(String? apiKey) {
  return implementation.fishAudioTransportCredential(apiKey);
}
