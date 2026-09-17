import 'dart:typed_data';

import 'capture_image_optimizer_native.dart'
    if (dart.library.js_interop) 'capture_image_optimizer_web.dart'
    as platform;

const int captureLongestEdge = 512;
const int captureJpegQuality = 65;

/// Shrinks camera images and strips metadata before storing or uploading them.
Future<Uint8List> optimizeCaptureBytes(Uint8List bytes) => platform
    .optimizeCaptureBytes(bytes, captureLongestEdge, captureJpegQuality);
