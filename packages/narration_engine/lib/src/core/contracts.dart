import 'models.dart';

abstract interface class SceneInterpreter {
  Future<SceneObservation> interpret(List<CapturedImage> captures);
}

abstract interface class NarrationModel {
  Future<NarrationDraft> narrate(NarrationRequest request);
}

abstract interface class SpeechSynthesizer {
  Future<AudioTrack> synthesize(String text);
}

/// The engine controls sequencing; implementations provide platform playback.
abstract interface class AudioOutput {
  /// Returns after playback starts. [AudioPlayback.completed] settles when the
  /// track finishes or playback fails.
  Future<AudioPlayback> play(AudioTrack track);

  Future<void> stop();
}

typedef Clock = DateTime Function();
