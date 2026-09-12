/// A model-safe OpenRouter TTS choice.
///
/// Voice identifiers belong to a specific speech model. Using a preset keeps
/// the two values together while the synthesizer's string constructor remains
/// available for advanced or newly released voices.
final class OpenRouterVoiceOption {
  const OpenRouterVoiceOption({
    required this.name,
    required this.model,
    required this.voiceId,
  });

  final String name;
  final String model;
  final String voiceId;

  static const davidAttenborough = OpenRouterVoiceOption(
    name: 'david-attenborough',
    model: 'fish-audio/s2.1-pro',
    voiceId: 'c39a76f685cf4f8fb41cd5d3d66b497d',
  );

  static const morganFreeman = OpenRouterVoiceOption(
    name: 'morgan-freeman',
    model: 'fish-audio/s2.1-pro',
    voiceId: '3ad4d432023c47ee9e6c7805b973630a',
  );

  static const jade = OpenRouterVoiceOption(
    name: 'jade',
    model: 'x-ai/grok-voice-tts-1.0',
    voiceId: 'eve',
  );

  static const values = <OpenRouterVoiceOption>[
    morganFreeman,
    davidAttenborough,
    jade,
  ];

  static OpenRouterVoiceOption? named(String name) {
    final normalized = name.trim().toLowerCase();
    for (final option in values) {
      if (option.name == normalized) return option;
    }
    return null;
  }
}
