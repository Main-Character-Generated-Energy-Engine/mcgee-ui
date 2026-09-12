import 'dart:typed_data';

import '../core/contracts.dart';
import '../core/models.dart';
import '../openai/openai_http_client.dart';
import 'openrouter_voice_option.dart';

/// OpenRouter speech synthesis with raw MP3 output.
final class OpenRouterSpeechSynthesizer implements SpeechSynthesizer {
  const OpenRouterSpeechSynthesizer({
    required this.client,
    this.model = 'fish-audio/s2.1-pro',
    this.voice = '3ad4d432023c47ee9e6c7805b973630a',
  });

  factory OpenRouterSpeechSynthesizer.withVoice({
    required OpenAiApi client,
    required OpenRouterVoiceOption voice,
  }) {
    return OpenRouterSpeechSynthesizer(
      client: client,
      model: voice.model,
      voice: voice.voiceId,
    );
  }

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
      'response_format': 'mp3',
    });
    if (bytes.isEmpty) {
      throw StateError('Speech synthesis returned an empty MP3');
    }
    return AudioTrack(id: 'openrouter-mp3-${text.hashCode}', bytes: bytes);
  }
}
