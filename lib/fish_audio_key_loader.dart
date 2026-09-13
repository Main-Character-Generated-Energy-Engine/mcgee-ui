import 'fish_audio_key_loader_stub.dart'
    if (dart.library.io) 'fish_audio_key_loader_io.dart'
    as implementation;

Future<String?> loadDefaultFishAudioKey({
  String path = '.secrets/fishaudio-key',
}) {
  return implementation.loadDefaultFishAudioKey(path: path);
}
