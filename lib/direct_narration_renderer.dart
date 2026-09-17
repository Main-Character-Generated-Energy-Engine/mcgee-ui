import 'package:mcgee/narration_engine.dart';
import 'package:mcgee/openrouter.dart';

/// Writes a complete passage before starting browser speech.
final class DirectNarrationRenderer implements NarrationRenderer {
  DirectNarrationRenderer({
    required this.narrator,
    required this.speech,
  });

  final OpenRouterNarrationModel narrator;
  final SpeechSynthesizer speech;

  @override
  Future<RenderedNarration> render(NarrationRequest request) async {
    final draft = await narrator.narrate(request);
    final text = draft.text?.trim();
    if (!draft.shouldSpeak || text == null || text.isEmpty) {
      throw const FormatException('The narrator returned no spoken passage.');
    }
    final track = await speech.synthesize(text);
    return RenderedNarration(draft: draft, track: track);
  }
}
