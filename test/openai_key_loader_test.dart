import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcgee/openai_key_loader.dart';

void main() {
  test('loads and trims the default OpenAI key file', () async {
    final directory = await Directory.systemTemp.createTemp('mcgee-key-test-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/openai-key');
    await file.writeAsString('  test-key  \n');

    expect(await loadDefaultOpenAiKey(path: file.path), 'test-key');
  });

  test('returns null when the default key file is missing', () async {
    final directory = await Directory.systemTemp.createTemp('mcgee-key-test-');
    addTearDown(() => directory.delete(recursive: true));

    expect(
      await loadDefaultOpenAiKey(path: '${directory.path}/missing-openai-key'),
      isNull,
    );
  });
}
