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
          'Inspect the attached captures for the current visible action. '
          'They are ordered oldest to newest; the latest image is authoritative.',
      fingerprint: 'direct-captures:${captures.last.id}',
      details: const <String, String>{
        'instruction':
            'Describe the visible subject, concrete action or posture, and '
            'an identifiable object or spatial detail. A single still image '
            'does not establish a movement sequence. Do not invent unseen '
            'actions. Connect this visible moment to the preceding narration; '
            'keep any theatrical interpretation subordinate to the action.',
      },
    );
  }
}
