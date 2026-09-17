import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mcgee/direct_narration_renderer.dart';
import 'package:mcgee/narration_engine.dart';
import 'package:mcgee/openai.dart';
import 'package:mcgee/openrouter.dart';

void main() {
  test('writes and validates story state before starting speech', () async {
    final writer = _Writer();
    final speech = _Speech();
    final renderer = DirectNarrationRenderer(
      narrator: OpenRouterNarrationModel(
        client: writer,
        requireSpokenLine: true,
        characterName: 'Ari',
      ),
      speech: speech,
    );
    final rendered = await renderer.render(const NarrationRequest(
      prompt: 'Continue the story.',
      observation: SceneObservation(description: 'A door.', fingerprint: 'door'),
      captures: [],
      memory: NarrativeMemorySnapshot(),
    ));
    expect(rendered.draft.text, 'Ari pauses at the door.');
    expect(rendered.draft.canonUpdates['open_thread'], 'Will Ari enter?');
    expect(speech.texts, ['Ari pauses at the door.']);
    await rendered.track.dispose();
  });
}

final class _Writer implements OpenAiApi {
  @override
  Future<Map<String, Object?>> createResponse(Map<String, Object?> body) async => {
    'output_text':
        '{"action":"speak","text":"Ari pauses at the door.",'
        '"reason":"Visible movement.","motifs":["door"],'
        '"canon_updates":[{"key":"open_thread","value":"Will Ari enter?"}]}',
  };

}

final class _Speech implements SpeechSynthesizer {
  final texts = <String>[];

  @override
  Future<AudioTrack> synthesize(String text) async {
    texts.add(text);
    return AudioTrack.fromBytes(id: 'test', bytes: Uint8List.fromList([1]));
  }
}
