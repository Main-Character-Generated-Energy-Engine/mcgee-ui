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
          'The attached captures are chronological. Interpret only their '
          'visible action and meaningful change.',
      fingerprint: 'direct-captures:${captures.last.id}',
      details: const <String, String>{
        'instruction': 'Describe only what is visible in the attached images.',
      },
    );
  }
}
