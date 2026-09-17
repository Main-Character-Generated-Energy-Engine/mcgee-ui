import 'dart:typed_data';

import 'capture_path_reader_stub.dart'
    if (dart.library.io) 'capture_path_reader_io.dart'
    as implementation;

Future<Uint8List> readCapturePath(String path) {
  return implementation.readCapturePath(path);
}
