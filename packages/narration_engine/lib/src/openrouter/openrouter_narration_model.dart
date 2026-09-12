import '../core/contracts.dart';
import '../core/models.dart';
import '../openai/openai_http_client.dart';
import '../openai/openai_narration_model.dart';

/// Editorial/comedy pass using Sol through OpenRouter.
final class OpenRouterNarrationModel implements NarrationModel {
  OpenRouterNarrationModel({
    required OpenAiApi client,
    this.model = 'openai/gpt-5.6-sol',
    this.requireSpokenLine = false,
  }) : _delegate = OpenAiNarrationModel(
         client: client,
         model: model,
         requireSpokenLine: requireSpokenLine,
       );

  final String model;
  final bool requireSpokenLine;
  final OpenAiNarrationModel _delegate;

  @override
  Future<NarrationDraft> narrate(NarrationRequest request) {
    return _delegate.narrate(request);
  }
}
