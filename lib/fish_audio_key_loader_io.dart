import 'dart:io';

import 'package:narration_engine/fish_audio_io.dart';

Future<String?> loadDefaultFishAudioKey({required String path}) async {
  final file = File(path);
  if (!await file.exists()) return null;
  return loadFishAudioApiKey(file);
}
