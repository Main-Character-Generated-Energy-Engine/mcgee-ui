import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcgee/capture_store.dart';
import 'package:mcgee/narrator_profile.dart';
import 'package:mcgee/openrouter_runtime.dart';
import 'package:narration_engine/narration_engine.dart';
import 'package:narration_engine/openrouter.dart';

void main() {
  test('rapid voice changes suppress captures until all stops finish and keep story', () async {
    final output = _DelayedAudioOutput();
    final memory = NarrativeMemory.fromSnapshot(NarrativeMemorySnapshot(
      recentNarrations: [
        NarrationMemoryEntry(
          text: 'Ari had struggled to find the words for an apology.',
          observedAt: DateTime.utc(2026),
        ),
      ],
    ));
    final runtime = OpenRouterNarrationRuntime(
      apiKey: 'test-key',
      audioOutput: output,
      characterName: 'Ari',
      memory: memory,
      narratorProfiles: {
        for (final voice in OpenRouterVoiceOption.values)
          voice.name: NarratorProfile(
            openingInstructions: '${voice.name} opening',
            liveInstructions: '${voice.name} live',
          ),
      },
    );
    final david = runtime.setVoice(OpenRouterVoiceOption.davidAttenborough);
    final eve = runtime.setVoice(OpenRouterVoiceOption.jade);
    expect(runtime.voice, OpenRouterVoiceOption.jade);
    expect(output.stops, hasLength(2));
    final capture = StoredCapture(bytes: Uint8List.fromList([1]));
    expect(await runtime.addCapture(capture: capture, capturedAt: DateTime.utc(2026)), isNull);

    // The last request can finish first; the earlier pending stop still blocks capture.
    output.stops[1].complete();
    await eve;
    expect(await runtime.addCapture(capture: capture, capturedAt: DateTime.utc(2026)), isNull);
    output.stops[0].complete();
    await david;
    expect(runtime.voice, OpenRouterVoiceOption.jade);
    expect(runtime.memory.recentNarrations.single.text, memory.snapshot.recentNarrations.single.text);
    final closing = runtime.close();
    output.stops.last.complete();
    await closing;
  });
}

final class _DelayedAudioOutput implements AudioOutput {
  final List<Completer<void>> stops = [];

  @override
  Future<AudioPlayback> play(AudioTrack track) => throw UnimplementedError();

  @override
  Future<void> stop() {
    final stopped = Completer<void>();
    stops.add(stopped);
    return stopped.future;
  }
}
