import 'dart:io';

/// Loads a Fish Audio key without placing it in arguments, logs, or source.
Future<String> loadFishAudioApiKey(File file) async {
  if (!await file.exists()) {
    throw FileSystemException(
      'Fish Audio API key file does not exist',
      file.path,
    );
  }
  final key = (await file.readAsString()).trim();
  if (key.isEmpty) {
    throw const FormatException('Fish Audio API key file is empty');
  }
  if (key.contains(RegExp(r'\s'))) {
    throw const FormatException(
      'Fish Audio API key must not contain whitespace',
    );
  }
  return key;
}
