import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;

/// Native builds keep the image work off the UI isolate.
Future<Uint8List> optimizeCaptureBytes(
  Uint8List bytes,
  int longestEdge,
  int quality,
) => compute(_optimizeCaptureBytes, (bytes, longestEdge, quality));

Uint8List _optimizeCaptureBytes((Uint8List, int, int) request) {
  final (bytes, longestEdge, quality) = request;
  final decoded = image.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Camera capture is not a supported image.');
  }

  final oriented = image.bakeOrientation(decoded);
  final sourceLongestEdge = oriented.width > oriented.height
      ? oriented.width
      : oriented.height;
  final targetWidth = oriented.width >= oriented.height ? longestEdge : null;
  final targetHeight = oriented.height > oriented.width ? longestEdge : null;
  final resized = sourceLongestEdge <= longestEdge
      ? oriented
      : image.copyResize(
          oriented,
          width: targetWidth,
          height: targetHeight,
          interpolation: image.Interpolation.average,
        );

  return image.encodeJpg(resized, quality: quality);
}
