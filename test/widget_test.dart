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

  testWidgets('starts with narrator setup and advances without an API key', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MainApp(home: CameraCapturePage(ioApiKeyOverride: 'sk-or-test')),
    );
    await tester.pump();

    expect(find.bySemanticsLabel('MCgEe'), findsOneWidget);
    expect(
      find.text(
        'Morgan Freeman is ready. A different voice may audition below.',
      ),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('enable-camera-button')), findsNothing);
    final morganAvatar = find.byKey(
      const ValueKey('setup-actor-Morgan Freeman'),
    );
    expect(find.byKey(const ValueKey('setup-actor-Eve')), findsOneWidget);
    expect(morganAvatar, findsOneWidget);
    expect(
      find.byKey(const ValueKey('setup-actor-David Attenborough')),
      findsOneWidget,
    );
    expect(tester.widget<Semantics>(morganAvatar).properties.selected, isTrue);
    final languageSelector = find.byKey(
      const ValueKey('narration-language-selector'),
    );
    expect(languageSelector, findsOneWidget);
    expect(find.text('English'), findsOneWidget);
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

    expect(find.byKey(const ValueKey('openrouter-key-field')), findsNothing);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('continue-setup-button')));
      // The IO host checks for optional local credential files before it
      // builds the runtime; allow those real filesystem futures to finish.
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    final consentHeading = find.text('Your story is waiting.');
    for (
      var attempt = 0;
      attempt < 20 && consentHeading.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(tester.takeException(), isNull);
    expect(consentHeading, findsOneWidget);
    expect(
      find.textContaining('Morgan Freeman has cleared their throat'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('enable-camera-button')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
