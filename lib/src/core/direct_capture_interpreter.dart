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
          'Live camera captures are attached, oldest to newest. '
          'Latest capture: ${captures.last.id}.',
      fingerprint: 'direct-captures:${captures.last.id}',
    );
  }
}
