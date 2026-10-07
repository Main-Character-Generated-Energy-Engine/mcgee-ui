import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcgee/main.dart';
import 'package:mcgee/narration_diagnostics.dart';
import 'package:mcgee/narration_error_card.dart';

void main() {
  test(
    'report retains the cause and redacts credentials before truncating',
    () {
      final report = NarrationDiagnostics(
        stage: 'Opening playback',
        error: StateError(
          'NotAllowedError: play() was blocked. '
          'Bearer fish-secret, sk-or-test-secret, native-secret',
        ),
        narrator: 'Eve',
        language: 'English',
        credential: 'native-secret',
        stackTrace: StackTrace.fromString('player.start\nengine.speak'),
      ).report;
      expect(report, contains('NotAllowedError: play() was blocked'));
      expect(report, contains('player.start'));
      expect(report, isNot(contains('fish-secret')));
      expect(report, isNot(contains('sk-or-test-secret')));
      expect(report, isNot(contains('native-secret')));
      expect(NarrationDiagnostics.redact('x' * 7000).length, lessThan(6100));
    },
  );

  testWidgets('small phone can copy a long report when clipboard is blocked', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          throw PlatformException(code: 'clipboard-blocked');
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    final report =
        'Error: narration could not decode.\n${'Stack frame\n' * 80}';
    await tester.pumpWidget(
      MainApp(
        home: Scaffold(
          body: SafeArea(
            child: NarrationErrorCard(
              message: 'Opening narration could not play.',
              report: report,
              onReturnToSelection: () {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('copy-narration-error')));
    await tester.pump();
    expect(find.textContaining('Copy was blocked.'), findsOneWidget);
    expect(find.text('Copied'), findsNothing);
    expect(
      tester
          .widget<SelectableText>(
            find.byKey(const ValueKey('narration-error-details')),
          )
          .data,
      report,
    );
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -400),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
