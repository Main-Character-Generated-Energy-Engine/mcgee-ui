/// A Fish Audio voice paired with its TTS model.
///
/// Voice identifiers belong to a specific speech model. Using a preset keeps
/// the two values together across browser and native hosts.
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
    model: 's2.1-pro-free',
    voiceId: 'c39a76f685cf4f8fb41cd5d3d66b497d',
  );

  static const morganFreeman = OpenRouterVoiceOption(
    name: 'morgan-freeman',
    model: 's2.1-pro-free',
    voiceId: '3ad4d432023c47ee9e6c7805b973630a',
  );

  static const jade = OpenRouterVoiceOption(
    name: 'jade',
    model: 's2.1-pro-free',
    voiceId: '1e5902ed8ddf433b88a717444bb90510',
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
