import 'package:narration_engine/fish_audio.dart';

import 'fish_audio_transport_io.dart'
    if (dart.library.js_interop) 'fish_audio_transport_web.dart'
    as implementation;

FishAudioWebSocketTransport createFishAudioTransport() {
  return implementation.createFishAudioTransport();
}

/// Dart IO sends this credential to Fish directly. On web, the localhost relay
/// owns the real credential and the transport deliberately ignores this value.
String fishAudioTransportCredential(String? apiKey) {
  return implementation.fishAudioTransportCredential(apiKey);
}
