import 'dart:io';

import 'package:narration_engine/src/openai/capture.dart';
import 'package:test/test.dart';

void main() {
  test('loads timestamp-named JPEGs in chronological order', () async {
    final directory = await Directory.systemTemp.createTemp('capture-order-');
    addTearDown(() => directory.delete(recursive: true));
    await File('${directory.path}/20.jpg').writeAsBytes([2]);
    await File('${directory.path}/notes.txt').writeAsString('ignore');
    await File('${directory.path}/3.JPEG').writeAsBytes([3]);
    await File('${directory.path}/11.jpg').writeAsBytes([1]);

    final captures = await loadTimestampedJpegs(directory);

    expect(captures.map((capture) => capture.id), [
      '3.JPEG',
      '11.jpg',
      '20.jpg',
    ]);
    expect(captures.first.capturedAt.millisecondsSinceEpoch, 3000);
  });
}
