import 'dart:io';

/// Loads an OpenRouter key without placing it in arguments, logs, or source.
Future<String> loadOpenRouterApiKey(File file) async {
  if (!await file.exists()) {
    throw FileSystemException(
      'OpenRouter API key file does not exist',
      file.path,
    );
  }
  final key = (await file.readAsString()).trim();
  if (key.isEmpty) {
    throw const FormatException('OpenRouter API key file is empty');
  }
  if (key.contains(RegExp(r'\s'))) {
    throw const FormatException(
      'OpenRouter API key must not contain whitespace',
    );
  }
  return key;
}
