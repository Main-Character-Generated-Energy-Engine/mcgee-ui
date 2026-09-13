import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcgee/openrouter_key_loader.dart';

void main() {
  test('loads and trims the default OpenRouter key file', () async {
    final directory = await Directory.systemTemp.createTemp('mcgee-key-test-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/openrouter-key');
    await file.writeAsString('  test-key  \n');

    expect(await loadDefaultOpenRouterKey(path: file.path), 'test-key');
  });

  test('returns null when the default key file is missing', () async {
    final directory = await Directory.systemTemp.createTemp('mcgee-key-test-');
    addTearDown(() => directory.delete(recursive: true));

    expect(
      await loadDefaultOpenRouterKey(
        path: '${directory.path}/missing-openrouter-key',
      ),
      isNull,
    );
  });
}
