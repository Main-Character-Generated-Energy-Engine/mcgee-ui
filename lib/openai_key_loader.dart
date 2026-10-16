import 'openai_key_loader_stub.dart'
    if (dart.library.io) 'openai_key_loader_io.dart'
    as implementation;

Future<String?> loadDefaultOpenAiKey({String path = '.secrets/openai-key'}) {
  return implementation.loadDefaultOpenAiKey(path: path);
}
