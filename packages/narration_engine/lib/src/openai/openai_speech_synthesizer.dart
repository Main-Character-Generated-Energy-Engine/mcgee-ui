import 'dart:typed_data';

import '../core/contracts.dart';
import '../core/models.dart';
import 'openai_http_client.dart';

final class OpenAiSpeechSynthesizer implements SpeechSynthesizer {
  const OpenAiSpeechSynthesizer({
    required this.client,
    this.model = 'gpt-4o-mini-tts',
    this.voice = 'onyx',
  });

  final OpenAiApi client;
  final String model;
  final String voice;

  @override
  Future<AudioTrack> synthesize(String text) async {
    if (text.trim().isEmpty) {
      throw ArgumentError.value(text, 'text', 'Speech text must not be empty');
    }
    final Uint8List bytes = await client.createSpeech({
      'model': model,
      'voice': voice,
      'input': text,
      'instructions':
          'Speak as the commanding narrator of a thunderous cinematic epic. '
          'Sound grave, urgent, and certain that history is about to turn. '
          'Use dramatic pauses and escalating weight without shouting.',
      'response_format': 'mp3',
      'speed': 0.95,
    });
    if (bytes.isEmpty) {
      throw StateError('Speech synthesis returned an empty MP3');
    }
    return AudioTrack(id: 'openai-mp3-${text.hashCode}', bytes: bytes);
  }
}
