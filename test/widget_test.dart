// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:mcgee/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('builds the app shell with an injected home', (tester) async {
    await tester.pumpWidget(const MainApp(home: Scaffold(body: Text('MCGEE'))));

    expect(find.text('MCGEE'), findsOneWidget);
  });

  testWidgets('accepts an OpenRouter key without a framework exception', (
    tester,
  ) async {
    await tester.pumpWidget(const MainApp());
    for (var attempt = 0; attempt < 10; attempt++) {
      final keyUiIsReady =
          find.text('Connect OpenRouter').evaluate().isNotEmpty ||
          find.text('Narrator ready').evaluate().isNotEmpty ||
          find.text('Enter key').evaluate().isNotEmpty;
      if (keyUiIsReady) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    if (find.text('Connect OpenRouter').evaluate().isEmpty) {
      final keyButton = find.text('Narrator ready').evaluate().isNotEmpty
          ? find.text('Narrator ready')
          : find.text('Enter key');
      await tester.tap(keyButton);
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(find.text('Connect OpenRouter'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'sk-or-test');
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
