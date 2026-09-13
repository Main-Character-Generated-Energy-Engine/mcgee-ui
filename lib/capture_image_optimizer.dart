import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;

const int captureLongestEdge = 512;
const int captureJpegQuality = 65;

/// Resizes a camera JPEG to the resolution used by low-detail model vision.
///
/// Encoding through [image.encodeJpg] also removes camera metadata before the
/// frame is retained or uploaded. `compute` keeps this CPU work off the UI
/// isolate on platforms that support isolates.
Future<Uint8List> optimizeCaptureBytes(Uint8List bytes) {
  return compute(_optimizeCaptureBytes, bytes);
}

Uint8List _optimizeCaptureBytes(Uint8List bytes) {
  final decoded = image.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Camera capture is not a supported image.');
  }

  final oriented = image.bakeOrientation(decoded);
  final longestEdge = oriented.width > oriented.height
      ? oriented.width
      : oriented.height;
  final targetWidth = oriented.width >= oriented.height
      ? captureLongestEdge
      : null;
  final targetHeight = oriented.height > oriented.width
      ? captureLongestEdge
      : null;
  final resized = longestEdge <= captureLongestEdge
      ? oriented
      : image.copyResize(
          oriented,
          width: targetWidth,
          height: targetHeight,
          interpolation: image.Interpolation.average,
        );

  return image.encodeJpg(resized, quality: captureJpegQuality);
}
