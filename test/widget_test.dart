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

  testWidgets(
    'starts with narrator setup and advances when Enter is pressed',
    (tester) async {
      await tester.pumpWidget(const MainApp());
      await tester.pump();

      expect(find.bySemanticsLabel('MCgEe'), findsOneWidget);
      expect(find.byKey(const ValueKey('enable-camera-button')), findsNothing);
      final morganAvatar = find.byKey(
        const ValueKey('setup-actor-Morgan Freeman'),
      );
      final eveAvatar = find.byKey(const ValueKey('setup-actor-Eve'));
      expect(morganAvatar, findsOneWidget);
      expect(
        find.byKey(const ValueKey('setup-actor-David Attenborough')),
        findsOneWidget,
      );
      expect(eveAvatar, findsOneWidget);
      expect(
        tester.widget<Semantics>(morganAvatar).properties.selected,
        isTrue,
      );
      final avatarAssets = tester
          .widgetList<Image>(find.byType(Image))
          .map((widget) => (widget.image as AssetImage).assetName);
      expect(
        avatarAssets,
        containsAll(<String>[
          'lib/assets/morgan-avatar.webp',
          'lib/assets/david-avatar.webp',
          'lib/assets/eve-avatar.webp',
        ]),
      );

      await tester.tap(eveAvatar);
      await tester.pump();
      expect(tester.widget<Semantics>(eveAvatar).properties.selected, isTrue);

      final keyField = find.byKey(const ValueKey('openrouter-key-field'));
      final field = tester.widget<EditableText>(
        find.descendant(of: keyField, matching: find.byType(EditableText)),
      );
      expect(field.maxLines, 1);
      expect(field.expands, isFalse);
      expect(field.autofillHints, isNull);

      await tester.enterText(keyField, 'sk-or-test');
      tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.text('Your story is waiting.'), findsOneWidget);
      expect(
        find.textContaining('Eve has cleared their throat'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('enable-camera-button')),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
