import 'package:flutter_test/flutter_test.dart';
import 'package:mcgee/narrative_memory_store.dart';
import 'package:mcgee/user_profile_store.dart';
import 'package:narration_engine/narration_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('profile name is normalized and restored', () async {
    const store = SharedPreferencesUserProfileStore();

    await store.saveName('  Ari   Elkin  ');

    expect(await store.loadName(), 'Ari Elkin');
    expect(() => normalizeCharacterName('   '), throwsFormatException);
    expect(() => normalizeCharacterName('Ari\nElkin'), throwsFormatException);
  });

  test('spoken story memory survives a store round trip', () async {
    final store = SharedPreferencesNarrativeMemoryStore();
    final memory = NarrativeMemory(maxNarrations: 1)
      ..recordNarration(
        text: 'Ari opens the notebook.',
        observedAt: DateTime.utc(2026, 9, 15, 10),
      )
      ..recordNarration(
        text: 'Ari studies the page in solemn silence.',
        observedAt: DateTime.utc(2026, 9, 15, 10, 0, 2),
        canonUpdates: const <String, String>{'object': 'notebook'},
      );

    await store.save(characterName: 'Ari', snapshot: memory.snapshot);
    final restored = await SharedPreferencesNarrativeMemoryStore().load(
      characterName: 'Ari',
    );

    expect(restored.snapshot.storySummary, 'Ari opens the notebook.');
    expect(
      restored.snapshot.recentNarrations.single.text,
      'Ari studies the page in solemn silence.',
    );
    expect(restored.snapshot.canon, <String, String>{'object': 'notebook'});
  });

  test('malformed persisted story safely starts with empty memory', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'mcgee.narrativeMemory.v2': 'not-json',
    });

    final restored = await SharedPreferencesNarrativeMemoryStore().load(
      characterName: 'Ari',
    );

    expect(restored.snapshot.recentNarrations, isEmpty);
    expect(restored.snapshot.storySummary, isEmpty);
  });

  test('story memory is discarded when it belongs to another name', () async {
    final store = SharedPreferencesNarrativeMemoryStore();
    final memory = NarrativeMemory()
      ..recordNarration(
        text: 'Ari opens the notebook.',
        observedAt: DateTime.utc(2026, 9, 15, 10),
      );
    await store.save(characterName: 'Ari', snapshot: memory.snapshot);

    final restored = await SharedPreferencesNarrativeMemoryStore().load(
      characterName: 'Sam',
    );

    expect(restored.snapshot.recentNarrations, isEmpty);
  });
}
