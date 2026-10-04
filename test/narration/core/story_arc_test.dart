import 'package:mcgee/narration_engine.dart';
import 'package:mcgee/src/core/writer_instructions.dart';
import 'package:mcgee/src/openai/openai_http_client.dart';
import 'package:mcgee/src/openai/openai_narration_model.dart';
import 'package:test/test.dart';

void main() {
  test('arc survives history trimming, restore, and episode rollover', () {
    final memory = NarrativeMemory(maxNarrations: 2);
    for (var passage = 0; passage < 6; passage++) {
      memory.recordNarration(
        text: 'Spoken passage $passage.',
        observedAt: DateTime.utc(2026, 1, 1, 0, passage),
      );
    }
    expect(memory.snapshot.recentNarrations, hasLength(2));
    expect(memory.snapshot.spokenNarrationCount, 6);
    expect(storyArcInstruction(memory.snapshot), contains('6 of 6'));
    final restored = NarrativeMemory.fromSnapshot(memory.snapshot);
    expect(storyArcInstruction(restored.snapshot), contains('PAYOFF:'));
    restored.recordNarration(
      text: 'The small question reaches its answer.',
      observedAt: DateTime.utc(2026, 1, 1, 0, 6),
    );
    expect(storyArcInstruction(restored.snapshot), contains('1 of 6'));
    restored.recordNarration(
      text: 'A fresh host opening.',
      observedAt: DateTime.utc(2026, 1, 1, 0, 7),
      startsEpisode: true,
    );
    expect(restored.snapshot.spokenNarrationCount, 1);
    final reopened = NarrativeMemory.fromSnapshot(restored.snapshot);
    expect(reopened.snapshot.spokenNarrationCount, 1);
    expect(storyArcInstruction(reopened.snapshot), contains('1 of 6'));
    restored.clear();
    expect(restored.snapshot.spokenNarrationCount, 0);
    expect(storyArcInstruction(restored.snapshot), contains('SETUP:'));
  });

  test('observations leave arc position unchanged', () {
    final memory = NarrativeMemory()
      ..recordNarration(text: 'The opening.', observedAt: DateTime.utc(2026));
    for (var frame = 0; frame < 20; frame++) {
      memory.recordObservation(
        const SceneObservation(
          description: 'A seated subject.',
          fingerprint: 'unchanged',
        ),
      );
    }
    expect(memory.snapshot.hasOnlyOpening, isTrue);
    expect(memory.snapshot.spokenNarrationCount, 1);
    expect(storyArcInstruction(memory.snapshot), contains('1 of 6'));
  });

  test('legacy snapshots infer progress from available spoken history', () {
    final restored = NarrativeMemory.fromSnapshot(
      NarrativeMemorySnapshot(
        recentNarrations: [
          NarrationMemoryEntry(
            text: 'An opening.',
            observedAt: DateTime.utc(2026),
          ),
        ],
      ),
    );
    expect(restored.snapshot.spokenNarrationCount, 1);
    expect(storyArcInstruction(restored.snapshot), contains('SETUP:'));
  });

  test(
    'structured web and native stream receive the same next arc beat',
    () async {
      final api = _Api();
      final model = OpenAiNarrationModel(
        client: api,
        requireSpokenLine: true,
        continuous: true,
        narratorInstructions: () => 'MODE: DAVID',
      );
      const request = NarrationRequest(
        prompt: 'A seated subject.',
        observation: SceneObservation(
          description: 'Seated.',
          fingerprint: 'same',
        ),
        captures: [],
        memory: NarrativeMemorySnapshot(spokenNarrationCount: 6),
      );
      await model.narrate(request);
      final web = api.bodies.last['instructions'] as String;
      final stream = await model.narrateStream(request);
      await stream.textDeltas.join();
      await stream.completed;
      final native = api.bodies.last['instructions'] as String;
      expect(web, contains(storyArcInstruction(request.memory)));
      expect(native, contains(storyArcInstruction(request.memory)));
      expect(web, contains('PAYOFF:'));
    },
  );
}

final class _Api implements StreamingOpenAiApi {
  final bodies = <Map<String, Object?>>[];

  @override
  Future<Map<String, Object?>> createResponse(Map<String, Object?> body) async {
    bodies.add(body);
    return {
      'output_text':
          '{"action":"speak","text":"The specimen stays seated.",'
          '"reason":"","motifs":[],"canon_updates":[]}',
    };
  }

  @override
  Stream<Map<String, Object?>> createResponseStream(
    Map<String, Object?> body,
  ) async* {
    bodies.add(body);
    yield {
      'type': 'response.output_text.delta',
      'delta': 'The specimen stays seated.',
    };
  }
}
