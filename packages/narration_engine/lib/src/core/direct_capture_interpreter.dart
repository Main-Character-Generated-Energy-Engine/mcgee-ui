import 'contracts.dart';
import 'models.dart';

/// Defers image understanding to a multimodal [NarrationModel].
///
/// This adapter contributes only a prompt marker; it never makes a provider
/// request. Use it with a narrator configured to include the source captures.
final class DirectCaptureInterpreter implements SceneInterpreter {
  const DirectCaptureInterpreter();

  @override
  Future<SceneObservation> interpret(List<CapturedImage> captures) async {
    if (captures.isEmpty) {
      throw ArgumentError.value(captures, 'captures', 'Must not be empty.');
    }
    return SceneObservation(
      description:
          'The attached captures are chronological evidence for an explicitly '
          'fictional, high-stakes interpretation of the unfolding action.',
      fingerprint: 'direct-captures:${captures.last.id}',
      details: const <String, String>{
        'instruction':
            'Use the images as dramatic evidence, then invent theatrical '
            'thoughts and motives while narrating the subject’s actions or '
            'deliberate inaction in exclusively third-person thriller '
            'voiceover; render inner monologue only as indirect narration.',
      },
    );
  }
}
