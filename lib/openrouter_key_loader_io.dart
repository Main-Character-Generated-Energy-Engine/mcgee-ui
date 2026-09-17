import 'dart:io';

import 'package:mcgee/openrouter_io.dart';

Future<String?> loadDefaultOpenRouterKey({required String path}) async {
  final file = File(path);
  if (!await file.exists()) return null;
  return loadOpenRouterApiKey(file);
}
