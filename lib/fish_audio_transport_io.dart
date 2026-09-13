import 'package:narration_engine/fish_audio_io.dart';

FishAudioWebSocketTransport createFishAudioTransport() {
  return const IoFishAudioWebSocketTransport();
}

String fishAudioTransportCredential(String? apiKey) {
  final key = apiKey?.trim() ?? '';
  if (key.isEmpty) {
    throw StateError('A Fish Audio API key is required on Dart IO.');
  }
  return key;
}
