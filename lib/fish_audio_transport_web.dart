import 'package:mcgee/fish_audio.dart';

FishAudioWebSocketTransport createFishAudioTransport() {
  throw UnsupportedError(
    'Browser WebSockets cannot set the Fish authorization header. '
    'Use direct Fish HTTP speech instead.',
  );
}

String fishAudioTransportCredential(String? apiKey) =>
    throw UnsupportedError('Browser Fish credentials use HTTP speech.');
