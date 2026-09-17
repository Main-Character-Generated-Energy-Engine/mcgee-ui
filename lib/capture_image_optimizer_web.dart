import 'dart:js_interop';
import 'dart:typed_data';

@JS('McGeeOptimizeCapture')
external JSPromise<JSUint8Array> _optimizeCapture(
  JSUint8Array bytes,
  JSNumber longestEdge,
  JSNumber quality,
);

/// Browser codecs resize and re-encode without running Dart JPEG loops on the
/// same event loop that paints the camera preview.
Future<Uint8List> optimizeCaptureBytes(
  Uint8List bytes,
  int longestEdge,
  int quality,
) async {
  final output = await _optimizeCapture(
    bytes.toJS,
    longestEdge.toJS,
    (quality / 100).toJS,
  ).toDart;
  return output.toDart;
}
