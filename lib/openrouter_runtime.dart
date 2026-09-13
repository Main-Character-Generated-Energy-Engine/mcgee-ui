import 'package:narration_engine/narration_engine.dart';
import 'package:narration_engine/openrouter.dart';

import 'capture_store.dart';

/// Thin host composition root for the independently testable package.
final class OpenRouterNarrationRuntime {
  OpenRouterNarrationRuntime._({
    required OpenRouterHttpClient client,
    required NarrationEngine engine,
    required _SelectableSpeechSynthesizer speechSynthesizer,
  }) : _client = client,
       _engine = engine,
       _speechSynthesizer = speechSynthesizer;

  factory OpenRouterNarrationRuntime({
    required String apiKey,
    required AudioOutput audioOutput,
    OpenRouterVoiceOption voice = OpenRouterVoiceOption.morganFreeman,
  }) {
    final key = apiKey.trim();
    if (key.isEmpty || key.contains(RegExp(r'\s'))) {
      throw const FormatException('The selected OpenRouter key is invalid.');
    }
    final client = OpenRouterHttpClient(apiKey: key);
    final speechSynthesizer = _SelectableSpeechSynthesizer(
      client: client,
      voice: voice,
    );
    return OpenRouterNarrationRuntime._(
      client: client,
      engine: NarrationEngine(
        // The narration model sees the latest image directly. A local scene
        // marker avoids a second, sequential vision request on the live path.
        sceneInterpreter: const DirectCaptureInterpreter(),
        narrator: OpenRouterNarrationModel(
          client: client,
          requireSpokenLine: true,
          includeCaptures: true,
          continuous: true,
          maximumWords: 20,
        ),
        speechSynthesizer: speechSynthesizer,
        audioOutput: audioOutput,
        promptBuilder: const ContinuousDocumentaryPromptBuilder(
          maximumWords: 20,
        ),
        policy: const NarrationPolicy(
          minimumGap: Duration.zero,
          maximumObservationAge: Duration(seconds: 6),
          rollingWindow: Duration.zero,
          maxNarrationsPerWindow: 1,
          minimumSalience: 0,
          sceneLookback: 0,
          maximumWords: 20,
          rejectRepeatedNarration: false,
        ),
        maxCapturesPerObservation: 1,
        // Prepare from fresh frames during playback. Only the newest ready
        // passage survives, preventing a stale narration backlog.
        prefetchDuringPlayback: true,
        coalesceWhileBusy: true,
      ),
      speechSynthesizer: speechSynthesizer,
    );
  }

  final OpenRouterHttpClient _client;
  final NarrationEngine _engine;
  final _SelectableSpeechSynthesizer _speechSynthesizer;
  bool _closed = false;

  Stream<NarrationEngineEvent> get events => _engine.events;
  bool get isPlaying => _engine.isPlaying;

  Future<NarrationOutcome> speakStartupLine() {
    if (_closed) throw StateError('The narration runtime is closed.');
    return _engine.speak("It's time for some main character energy.");
  }

  Future<NarrationOutcome?> addCapture({
    required StoredCapture capture,
    required DateTime capturedAt,
  }) async {
    if (_closed) throw StateError('The narration runtime is closed.');
    final latestCapture = CapturedImage(
      source: 'webcam',
      capturedAt: capturedAt,
      path: capture.path,
      bytes: capture.bytes,
      protagonistHint: 'the recurring foreground camera holder',
    );
    return _engine.submit(<CapturedImage>[latestCapture]);
  }

  Future<void> stop() => _engine.stop();

  void setVoice(OpenRouterVoiceOption voice) {
    if (_closed) throw StateError('The narration runtime is closed.');
    _speechSynthesizer.voice = voice;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _engine.close();
    _client.close();
  }
}

final class _SelectableSpeechSynthesizer implements SpeechSynthesizer {
  _SelectableSpeechSynthesizer({required this.client, required this.voice});

  final OpenRouterHttpClient client;
  OpenRouterVoiceOption voice;

  @override
  Future<AudioTrack> synthesize(String text) {
    return OpenRouterSpeechSynthesizer.withVoice(
      client: client,
      voice: voice,
    ).synthesize(text);
  }
}
