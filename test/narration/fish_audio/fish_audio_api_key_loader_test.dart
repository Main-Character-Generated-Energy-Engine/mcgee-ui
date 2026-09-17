import 'dart:io';

import 'package:mcgee/fish_audio_io.dart';
import 'package:test/test.dart';

void main() {
  test('loads and trims a Fish Audio API key from a protected file', () async {
    final directory = await Directory.systemTemp.createTemp('fish-key-test-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/fishaudio-key');
    await file.writeAsString('fish-secret\n');

    expect(await loadFishAudioApiKey(file), 'fish-secret');
  });

  test('rejects a key containing whitespace', () async {
    final directory = await Directory.systemTemp.createTemp('fish-key-test-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/fishaudio-key');
    await file.writeAsString('not a key');

    await expectLater(loadFishAudioApiKey(file), throwsFormatException);
  });
}
