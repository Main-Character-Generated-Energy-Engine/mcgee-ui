import 'dart:typed_data';

abstract interface class CaptureStore {
  Future<StoredCapture> save({
    required int timestamp,
    required String sourcePath,
    required Future<Uint8List> Function() readBytes,
  });
}

final class StoredCapture {
  const StoredCapture({this.path, this.bytes})
    : assert((path == null) != (bytes == null));

  final String? path;
  final Uint8List? bytes;
}
