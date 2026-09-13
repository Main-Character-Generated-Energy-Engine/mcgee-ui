import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'capture_image_optimizer.dart';
import 'capture_store_types.dart';

Future<CaptureStore> createCaptureStore() async {
  final applicationSupport = await getApplicationSupportDirectory();
  final directory = Directory('${applicationSupport.path}/captures/webcam');
  await directory.create(recursive: true);
  return _IoCaptureStore(directory);
}

final class _IoCaptureStore implements CaptureStore {
  const _IoCaptureStore(this.directory);

  final Directory directory;

  @override
  Future<StoredCapture> save({
    required int timestamp,
    required Future<Uint8List> Function() readBytes,
  }) async {
    final destination = File('${directory.path}/$timestamp.jpg');
    final optimized = await optimizeCaptureBytes(await readBytes());
    await destination.writeAsBytes(optimized, flush: true);
    return StoredCapture(path: destination.path);
  }
}
