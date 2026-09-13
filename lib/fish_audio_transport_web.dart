import 'package:narration_engine/fish_audio.dart';

FishAudioWebSocketTransport createFishAudioTransport() {
  throw UnsupportedError(
    'Direct Fish Audio transport is unavailable in browsers. '
    'Use the Netlify narration endpoint.',
  );
}

String fishAudioTransportCredential(String? apiKey) =>
    throw UnsupportedError('Fish Audio credentials must stay server-side.');
