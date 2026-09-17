import 'dart:convert';
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
    expect(writer.calls, 1);
    await rendered.track.dispose();
  });

  test('an unnamed passage goes to speech without a repair request', () async {
    final writer = _Writer(text: 'The door waits.');
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
    expect(writer.calls, 1);
    expect(speech.texts, ['The door waits.']);
    await rendered.track.dispose();
  });
}

final class _Writer implements OpenAiApi {
  _Writer({this.text = 'Ari pauses at the door.'});

  final String text;
  int calls = 0;

  @override
  Future<Map<String, Object?>> createResponse(Map<String, Object?> body) async {
    calls++;
    return {
      'output_text': jsonEncode({
        'action': 'speak',
        'text': text,
        'reason': '',
        'motifs': ['door'],
        'canon_updates': [
          {'key': 'open_thread', 'value': 'Will Ari enter?'},
        ],
      }),
    };
  }

}

final class _Speech implements SpeechSynthesizer {
  final texts = <String>[];

  @override
  Future<AudioTrack> synthesize(String text) async {
    texts.add(text);
    return AudioTrack.fromBytes(id: 'test', bytes: Uint8List.fromList([1]));
  }
}
