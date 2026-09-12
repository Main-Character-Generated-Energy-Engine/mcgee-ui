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
          'Speak as a restrained, intimate prestige nature-documentary narrator. '
          'Dryly amused, unhurried, and sincere; never sound like an announcer. '
          'Use a brief natural pause where the sentence invites it.',
      'response_format': 'mp3',
      'speed': 0.95,
    });
    if (bytes.isEmpty) {
      throw StateError('Speech synthesis returned an empty MP3');
    }
    return AudioTrack(id: 'openai-mp3-${text.hashCode}', bytes: bytes);
  }
}
