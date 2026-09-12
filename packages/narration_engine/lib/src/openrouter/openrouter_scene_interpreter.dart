import '../core/contracts.dart';
import '../core/models.dart';
import '../openai/openai_http_client.dart';
import '../openai/openai_scene_interpreter.dart';

/// Literal vision pass routed through OpenRouter's Responses API.
final class OpenRouterSceneInterpreter implements SceneInterpreter {
  OpenRouterSceneInterpreter({
    required OpenAiApi client,
    this.model = 'openai/gpt-4.1-mini',
  }) : _delegate = OpenAiSceneInterpreter(client: client, model: model);

  final String model;
  final OpenAiSceneInterpreter _delegate;

  @override
  Future<SceneObservation> interpret(List<CapturedImage> captures) {
    return _delegate.interpret(captures);
  }
}
