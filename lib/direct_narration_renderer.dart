import 'package:mcgee/narration_engine.dart';
import 'package:mcgee/openrouter.dart';

/// Writes and validates a complete passage before starting browser speech.
final class DirectNarrationRenderer implements NarrationRenderer {
  DirectNarrationRenderer({
    required this.narrator,
    required this.speech,
  });

  final OpenRouterNarrationModel narrator;
  final SpeechSynthesizer speech;

  @override
  Future<RenderedNarration> render(NarrationRequest request) async {
    NarrationDraft draft;
    try {
      draft = await narrator.narrate(request);
    } on FormatException catch (error) {
      if (!error.message.contains('name cadence')) rethrow;
      draft = await narrator.narrate(NarrationRequest(
        prompt: '${request.prompt}\nREWRITE: Correct the character name cadence. '
            'Preserve the established thread and return the complete story state.',
        observation: request.observation,
        captures: request.captures,
        memory: request.memory,
      ));
    }
    final text = draft.text?.trim();
    if (!draft.shouldSpeak || text == null || text.isEmpty) {
      throw const FormatException('The narrator returned no spoken passage.');
    }
    final track = await speech.synthesize(text);
    return RenderedNarration(draft: draft, track: track);
  }
}
