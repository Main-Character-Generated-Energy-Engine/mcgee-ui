// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcgee/main.dart';
import 'package:mcgee/narrative_memory_store.dart';
import 'package:mcgee/user_profile_store.dart';
import 'package:narration_engine/narration_engine.dart';

void main() {
  testWidgets('builds the app shell with an injected home', (tester) async {
    await tester.pumpWidget(const MainApp(home: Scaffold(body: Text('MCGEE'))));

    expect(find.text('MCGEE'), findsOneWidget);
  });

  testWidgets('starts with narrator setup and advances without an API key', (
    tester,
  ) async {
    await tester.pumpWidget(
      MainApp(
        home: CameraCapturePage(
          ioApiKeyOverride: 'sk-or-test',
          userProfileStore: _MemoryUserProfileStore('Ari'),
          narrativeMemoryStore: _MemoryNarrativeMemoryStore(),
        ),
      ),
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
    expect(
      find.text('Ari’s story will be told by Morgan Freeman.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('not-you-button')), findsOneWidget);
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
    await tester.ensureVisible(
      find.byKey(const ValueKey('continue-setup-button')),
    );
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('continue-setup-button')));
      // The IO host checks for optional local credential files before it
      // builds the runtime; allow those real filesystem futures to finish.
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    final consentHeading = find.text('Ari’s story is waiting.');
    for (
      var attempt = 0;
      attempt < 20 && consentHeading.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(tester.takeException(), isNull);
    expect(find.text('Ari’s story is waiting.'), findsOneWidget);
    expect(
      find.textContaining('Morgan Freeman has cleared their throat'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('enable-camera-button')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('asks once for a name and offers returning users an edit link', (
    tester,
  ) async {
    final profile = _MemoryUserProfileStore(null);
    await tester.pumpWidget(
      MainApp(
        home: CameraCapturePage(
          ioApiKeyOverride: 'sk-or-test',
          userProfileStore: profile,
          narrativeMemoryStore: _MemoryNarrativeMemoryStore(),
        ),
      ),
    );
    await tester.pump();

    final field = find.byKey(const ValueKey('user-name-field'));
    expect(field, findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('continue-setup-button')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('continue-setup-button')));
    await tester.pump();
    expect(find.text('Enter the name the narrator should use.'), findsOneWidget);

    await tester.enterText(field, '  Sam  ');
    await tester.ensureVisible(
      find.byKey(const ValueKey('continue-setup-button')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('continue-setup-button')));
    for (var attempt = 0; attempt < 20 && profile.name != 'Sam'; attempt++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(profile.name, 'Sam');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('returning user can reopen the prefilled name field', (
    tester,
  ) async {
    await tester.pumpWidget(
      MainApp(
        home: CameraCapturePage(
          userProfileStore: _MemoryUserProfileStore('Ari'),
          narrativeMemoryStore: _MemoryNarrativeMemoryStore(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('setup-actor-Eve')));
    await tester.pump();
    expect(find.text('Ari’s story will be told by Eve.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('not-you-button')));
    await tester.pump();

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('user-name-field')),
    );
    expect(field.controller!.text, 'Ari');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('does not attach old story memory when clearing a rename fails', (
    tester,
  ) async {
    final profile = _MemoryUserProfileStore('Ari');
    await tester.pumpWidget(
      MainApp(
        home: CameraCapturePage(
          ioApiKeyOverride: 'sk-or-test',
          userProfileStore: profile,
          narrativeMemoryStore: _MemoryNarrativeMemoryStore(
            throwOnClear: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('not-you-button')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('user-name-field')),
      'Sam',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('continue-setup-button')),
    );
    await tester.tap(find.byKey(const ValueKey('continue-setup-button')));
    await tester.pump();

    expect(profile.name, 'Ari');
    expect(
      find.text('Your profile could not be prepared. Please try again.'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

final class _MemoryUserProfileStore implements UserProfileStore {
  _MemoryUserProfileStore(this.name);

  String? name;

  @override
  Future<String?> loadName() async => name;

  @override
  Future<void> saveName(String name) async {
    this.name = name;
  }
}

final class _MemoryNarrativeMemoryStore implements NarrativeMemoryStore {
  _MemoryNarrativeMemoryStore({this.throwOnClear = false});

  final bool throwOnClear;
  NarrativeMemory memory = NarrativeMemory();

  @override
  Future<void> clear() async {
    if (throwOnClear) throw StateError('Simulated clear failure.');
    memory.clear();
  }

  @override
  Future<NarrativeMemory> load({required String characterName}) async => memory;

  @override
  Future<void> save({
    required String characterName,
    required NarrativeMemorySnapshot snapshot,
  }) async {
    memory = NarrativeMemory.fromSnapshot(snapshot);
  }
}
