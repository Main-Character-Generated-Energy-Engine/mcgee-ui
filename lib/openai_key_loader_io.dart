import 'dart:io';

import 'package:mcgee/openai_io.dart';

Future<String?> loadDefaultOpenAiKey({required String path}) async {
  final environmentKey = Platform.environment['OPENAI_API_KEY']?.trim();
  if (environmentKey != null && environmentKey.isNotEmpty) {
    if (environmentKey.contains(RegExp(r'\s'))) {
      throw const FormatException('OpenAI API key must not contain whitespace');
    }
    return environmentKey;
  }
  final file = File(path);
  if (!await file.exists()) return null;
  return loadOpenAiApiKey(file);
}
