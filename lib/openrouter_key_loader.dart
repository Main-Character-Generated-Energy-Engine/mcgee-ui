import 'openrouter_key_loader_stub.dart'
    if (dart.library.io) 'openrouter_key_loader_io.dart'
    as implementation;

Future<String?> loadDefaultOpenRouterKey({
  String path = '.secrets/openrouter-key',
}) {
  return implementation.loadDefaultOpenRouterKey(path: path);
}
