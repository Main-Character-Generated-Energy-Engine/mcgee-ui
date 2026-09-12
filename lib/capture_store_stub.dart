import 'dart:typed_data';

import 'capture_store_types.dart';

Future<CaptureStore> createCaptureStore() async => const _MemoryCaptureStore();

final class _MemoryCaptureStore implements CaptureStore {
  const _MemoryCaptureStore();

  @override
  Future<StoredCapture> save({
    required int timestamp,
    required String sourcePath,
    required Future<Uint8List> Function() readBytes,
  }) async {
    return StoredCapture(bytes: await readBytes());
  }
}
