import '../core/contracts.dart';
import '../core/models.dart';
import '../core/narration_language.dart';
import '../openai/openai_http_client.dart';
import '../openai/openai_narration_model.dart';

/// Editorial/comedy pass using Terra through OpenRouter.
final class OpenRouterNarrationModel implements StreamingNarrationModel {
  OpenRouterNarrationModel({
    required OpenAiApi client,
    this.model = 'openai/gpt-5.6-terra',
    this.requireSpokenLine = false,
    this.continuous = false,
    this.maximumWords = 24,
    this.includeCaptures = false,
    this.language = NarrationLanguage.english,
    this.characterName,
    this.narratorInstructions,
  }) : _delegate = OpenAiNarrationModel(
         client: client,
         model: model,
         requireSpokenLine: requireSpokenLine,
         continuous: continuous,
         maximumWords: maximumWords,
         includeCaptures: includeCaptures,
         language: language,
         characterName: characterName,
         narratorInstructions: narratorInstructions,
       );

  final String model;
  final bool requireSpokenLine;
  final bool continuous;
  final int maximumWords;
  final bool includeCaptures;
  final NarrationLanguage language;
  final String? characterName;

  /// Current host-supplied mode; evaluated for each request.
  final String Function()? narratorInstructions;
  final OpenAiNarrationModel _delegate;

  @override
  Future<NarrationDraft> narrate(NarrationRequest request) {
    return _delegate.narrate(request);
  }

  @override
  Future<NarrationTextStream> narrateStream(NarrationRequest request) {
    return _delegate.narrateStream(request);
  }
}
