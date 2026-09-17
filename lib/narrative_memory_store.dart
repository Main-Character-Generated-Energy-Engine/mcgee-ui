import 'dart:convert';

import 'package:mcgee/narration_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'user_profile_store.dart';

const _narrativeMemoryKey = 'mcgee.narrativeMemory.v2';
const _legacyNarrativeMemoryKey = 'mcgee.narrativeMemory.v1';

abstract interface class NarrativeMemoryStore {
  Future<NarrativeMemory> load({required String characterName});

  Future<void> save({
    required String characterName,
    required NarrativeMemorySnapshot snapshot,
  });

  Future<void> clear();
}

final class SharedPreferencesNarrativeMemoryStore
    implements NarrativeMemoryStore {
  SharedPreferencesNarrativeMemoryStore();

  Future<void> _pendingWrite = Future<void>.value();

  @override
  Future<NarrativeMemory> load({required String characterName}) async {
    final owner = normalizeCharacterName(characterName);
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_narrativeMemoryKey);
    if (encoded == null) return NarrativeMemory();
    try {
      final value = jsonDecode(encoded);
      if (value is! Map ||
          value['version'] != 2 ||
          value['characterName'] != owner) {
        throw const FormatException('Unsupported narrative memory.');
      }
      final narrationValues = value['recentNarrations'];
      final narrations = <NarrationMemoryEntry>[];
      if (narrationValues is List) {
        for (final item in narrationValues) {
          if (item is! Map) continue;
          final text = item['text'];
          final observedAt = item['observedAt'];
          if (text is! String || text.trim().isEmpty || observedAt is! String) {
            continue;
          }
          final timestamp = DateTime.tryParse(observedAt);
          if (timestamp == null) continue;
          final motifValues = item['motifs'];
          narrations.add(
            NarrationMemoryEntry(
              text: text.trim(),
              observedAt: timestamp,
              motifs: motifValues is List
                  ? motifValues.whereType<String>().take(12).toList()
                  : const <String>[],
            ),
          );
        }
      }
      final canonValue = value['canon'];
      final canon = <String, String>{};
      if (canonValue is Map) {
        for (final entry in canonValue.entries) {
          if (entry.key is String && entry.value is String) {
            canon[entry.key as String] = entry.value as String;
          }
        }
      }
      return NarrativeMemory.fromSnapshot(
        NarrativeMemorySnapshot(
          recentNarrations: narrations,
          canon: canon,
          storySummary: value['storySummary'] is String
              ? value['storySummary'] as String
              : '',
        ),
      );
    } on Object {
      await preferences.remove(_narrativeMemoryKey);
      return NarrativeMemory();
    }
  }

  @override
  Future<void> save({
    required String characterName,
    required NarrativeMemorySnapshot snapshot,
  }) {
    final owner = normalizeCharacterName(characterName);
    final payload = jsonEncode(<String, Object?>{
      'version': 2,
      'characterName': owner,
      'storySummary': snapshot.storySummary,
      'recentNarrations': <Map<String, Object?>>[
        for (final narration in snapshot.recentNarrations)
          <String, Object?>{
            'text': narration.text,
            'observedAt': narration.observedAt.toUtc().toIso8601String(),
            'motifs': narration.motifs,
          },
      ],
      'canon': snapshot.canon,
    });
    return _queueWrite(() async {
      final preferences = await SharedPreferences.getInstance();
      if (!await preferences.setString(_narrativeMemoryKey, payload)) {
        throw StateError('The story could not be saved on this device.');
      }
    });
  }

  @override
  Future<void> clear() => _queueWrite(() async {
    final preferences = await SharedPreferences.getInstance();
    final removedCurrent = await preferences.remove(_narrativeMemoryKey);
    await preferences.remove(_legacyNarrativeMemoryKey);
    if (!removedCurrent) {
      throw StateError('The previous story could not be cleared.');
    }
  });

  Future<void> _queueWrite(Future<void> Function() operation) {
    final result = _pendingWrite.catchError((_) {}).then((_) => operation());
    _pendingWrite = result;
    return result;
  }
}
