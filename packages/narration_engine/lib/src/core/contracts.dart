import 'models.dart';

abstract interface class SceneInterpreter {
  Future<SceneObservation> interpret(List<CapturedImage> captures);
}

abstract interface class NarrationModel {
  Future<NarrationDraft> narrate(NarrationRequest request);
}

/// Optional narrator capability for incrementally synthesized speech.
abstract interface class StreamingNarrationModel implements NarrationModel {
  Future<NarrationTextStream> narrateStream(NarrationRequest request);
}

abstract interface class SpeechSynthesizer {
  Future<AudioTrack> synthesize(String text);
}

/// Optional TTS capability that accepts narration while it is being written.
///
/// Implementations must consume [textDeltas] in order. The returned synthesis
/// represents work that has already started; [StreamingSpeechSynthesis.completed]
/// settles once it has produced a complete track suitable for [AudioOutput].
abstract interface class StreamingSpeechSynthesizer
    implements SpeechSynthesizer {
  Future<StreamingSpeechSynthesis> synthesizeStream(Stream<String> textDeltas);
}

/// A running streaming-input speech synthesis operation.
abstract interface class StreamingSpeechSynthesis {
  Future<AudioTrack> get completed;

  /// Stops provider work when the narration is rejected or the engine stops.
  Future<void> cancel();
}

/// Optional fused provider for hosts that must keep provider credentials off
/// the client while still overlapping narration generation and synthesis.
abstract interface class NarrationRenderer {
  Future<RenderedNarration> render(NarrationRequest request);
}

/// The engine controls sequencing; implementations provide platform playback.
abstract interface class AudioOutput {
  /// Returns after playback starts. [AudioPlayback.completed] settles when the
  /// track finishes or playback fails.
  Future<AudioPlayback> play(AudioTrack track);

  Future<void> stop();
}

typedef Clock = DateTime Function();
