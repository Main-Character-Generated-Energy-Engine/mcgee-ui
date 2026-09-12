import 'dart:io';

/// Loads a key without placing it in command arguments, logs, or source code.
Future<String> loadOpenAiApiKey(File file) async {
  if (!await file.exists()) {
    throw FileSystemException('OpenAI API key file does not exist', file.path);
  }
  final key = (await file.readAsString()).trim();
  if (key.isEmpty) {
    throw const FormatException('OpenAI API key file is empty');
  }
  if (key.contains(RegExp(r'\s'))) {
    throw const FormatException('OpenAI API key must not contain whitespace');
  }
  return key;
}
