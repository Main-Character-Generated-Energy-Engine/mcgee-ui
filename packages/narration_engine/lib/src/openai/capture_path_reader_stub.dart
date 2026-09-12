import 'dart:typed_data';

Future<Uint8List> readCapturePath(String path) {
  throw UnsupportedError(
    'Path-backed captures are unavailable on this platform; provide bytes.',
  );
}
