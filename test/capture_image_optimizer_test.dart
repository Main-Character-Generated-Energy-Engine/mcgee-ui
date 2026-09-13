import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:mcgee/capture_image_optimizer.dart';

void main() {
  test('resizes and recompresses captures for low-detail vision', () async {
    final source = image.Image(width: 1440, height: 960);
    image.fill(source, color: image.ColorRgb8(110, 140, 170));
    final sourceBytes = image.encodeJpg(source, quality: 95);

    final optimized = await optimizeCaptureBytes(sourceBytes);
    final decoded = image.decodeJpg(optimized);

    expect(decoded, isNotNull);
    expect(decoded!.width, 512);
    expect(decoded.height, 341);
    expect(optimized.length, lessThan(sourceBytes.length));
  });
}
