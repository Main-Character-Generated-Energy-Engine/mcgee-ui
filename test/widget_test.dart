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
}
