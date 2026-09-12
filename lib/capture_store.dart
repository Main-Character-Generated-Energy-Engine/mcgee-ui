import 'capture_store_stub.dart'
    if (dart.library.io) 'capture_store_io.dart'
    as implementation;
import 'capture_store_types.dart';

export 'capture_store_types.dart';

Future<CaptureStore> createCaptureStore() {
  return implementation.createCaptureStore();
}
