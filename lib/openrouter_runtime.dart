import 'dart:async';
import 'dart:math';

import 'package:narration_engine/narration_engine.dart';
import 'package:narration_engine/fish_audio.dart';
import 'package:narration_engine/openrouter.dart';

import 'capture_store.dart';
import 'film_opening.dart';
import 'netlify_narration_renderer.dart';

/// Allows enough time for both multimodal writing and speech synthesis while
/// still preventing old camera frames from entering the live audio stream.
const liveMaximumObservationAge = Duration(seconds: 20);

/// Thin host composition root for the independently testable package.
final class OpenRouterNarrationRuntime {
  OpenRouterNarrationRuntime._({
    required OpenRouterHttpClient client,
    required NarrationEngine engine,
    required _SelectableSpeechSynthesizer speechSynthesizer,
    required NarrationLanguage language,
    required String characterName,
    NetlifyNarrationRenderer? netlifyRenderer,
  }) : _client = client,
       _engine = engine,
       _speechSynthesizer = speechSynthesizer,
       _language = language,
       _characterName = characterName,
       _netlifyRenderer = netlifyRenderer;

  factory OpenRouterNarrationRuntime({
    String? apiKey,
    required AudioOutput audioOutput,
    required String characterName,
    OpenRouterVoiceOption voice = OpenRouterVoiceOption.morganFreeman,
    NarrationLanguage language = NarrationLanguage.english,
    String? fishAudioCredential,
    FishAudioWebSocketTransport? fishAudioTransport,
    Uri? narrationEndpoint,
    NarrativeMemory? memory,
  }) {
    final normalizedCharacterName = characterName.trim();
    if (normalizedCharacterName.isEmpty) {
      throw ArgumentError.value(
        characterName,
        'characterName',
        'Must not be empty.',
      );
    }
    final key = apiKey?.trim();
    if (narrationEndpoint == null &&
        (key == null || key.isEmpty || key.contains(RegExp(r'\s')))) {
      throw const FormatException('The selected OpenRouter key is invalid.');
    }
    final client = OpenRouterHttpClient(apiKey: key ?? 'server-managed');
    final random = Random();
    final netlifyRenderer = narrationEndpoint == null
        ? null
        : NetlifyNarrationRenderer(
            endpoint: narrationEndpoint,
            voice: voice,
            language: language,
            characterName: normalizedCharacterName,
          );
    final speechSynthesizer = _SelectableSpeechSynthesizer(
      client: client,
      voice: voice,
      fishAudioCredential: fishAudioCredential,
      fishAudioTransport: fishAudioTransport,
      remoteSynthesizer: netlifyRenderer,
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
          language: language,
          characterName: normalizedCharacterName,
        ),
        speechSynthesizer: speechSynthesizer,
        audioOutput: audioOutput,
        narrationRenderer: netlifyRenderer,
        promptBuilder: ContinuousDocumentaryPromptBuilder(
          maximumWords: 20,
          language: language,
          characterName: normalizedCharacterName,
        ),
        memory: memory,
        policy: const NarrationPolicy(
          minimumGap: Duration.zero,
          maximumObservationAge: liveMaximumObservationAge,
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
        narrationPause: () =>
            Duration(milliseconds: 500 + random.nextInt(1501)),
      ),
      speechSynthesizer: speechSynthesizer,
      language: language,
      characterName: normalizedCharacterName,
      netlifyRenderer: netlifyRenderer,
    );
  }

  final OpenRouterHttpClient _client;
  final NarrationEngine _engine;
  final _SelectableSpeechSynthesizer _speechSynthesizer;
  final NarrationLanguage _language;
  final String _characterName;
  final NetlifyNarrationRenderer? _netlifyRenderer;
  bool _closed = false;

  Stream<NarrationEngineEvent> get events => _engine.events;
  bool get isPlaying => _engine.isPlaying;
  NarrativeMemorySnapshot get memory => _engine.memory;

  Future<PreparedFilmOpening> prepareOpening({
    required void Function(FilmOpening) onCredits,
  }) async {
    if (_closed) throw StateError('The narration runtime is closed.');
    final opening = await (_netlifyRenderer?.generateOpening() ??
        generateFilmOpening(_client, _language, characterName: _characterName));
    if (_closed) throw StateError('The narration runtime is closed.');
    onCredits(opening);
    final track = await _speechSynthesizer
        .synthesize(opening.narration)
        .timeout(const Duration(seconds: 20));
    if (_closed) throw StateError('The narration runtime is closed.');
    return PreparedFilmOpening(opening: opening, track: track);
  }

  Future<NarrationOutcome> speakOpening(PreparedFilmOpening opening) {
    if (_closed) throw StateError('The narration runtime is closed.');
    return _engine.speak(
      opening.opening.narration,
      preparedTrack: opening.track,
    );
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
    _netlifyRenderer?.voice = voice;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _engine.close();
    _netlifyRenderer?.close();
    _client.close();
  }
}

final class _SelectableSpeechSynthesizer implements StreamingSpeechSynthesizer {
  _SelectableSpeechSynthesizer({
    required this.client,
    required this.voice,
    this.fishAudioCredential,
    this.fishAudioTransport,
    this.remoteSynthesizer,
  });

  final OpenRouterHttpClient client;
  final String? fishAudioCredential;
  final FishAudioWebSocketTransport? fishAudioTransport;
  final SpeechSynthesizer? remoteSynthesizer;
  OpenRouterVoiceOption voice;
  bool _fishAudioUnavailable = false;

  @override
  Future<AudioTrack> synthesize(String text) {
    if (remoteSynthesizer case final remote?) return remote.synthesize(text);
    return _synthesizeWithOpenRouter(text);
  }

  @override
  Future<StreamingSpeechSynthesis> synthesizeStream(
    Stream<String> textDeltas,
  ) async {
    final credential = fishAudioCredential;
    final transport = fishAudioTransport;
    if (!_fishAudioUnavailable &&
        credential != null &&
        transport != null &&
        voice.model.startsWith('fish-audio/')) {
      try {
        final bufferedText = StringBuffer();
        final textCompleted = Completer<String>();
        final bufferedDeltas = textDeltas.transform<String>(
          StreamTransformer<String, String>.fromHandlers(
            handleData: (delta, sink) {
              bufferedText.write(delta);
              sink.add(delta);
            },
            handleError: (error, stackTrace, sink) {
              if (!textCompleted.isCompleted) {
                textCompleted.completeError(error, stackTrace);
              }
              sink.addError(error, stackTrace);
            },
            handleDone: (sink) {
              if (!textCompleted.isCompleted) {
                textCompleted.complete(bufferedText.toString());
              }
              sink.close();
            },
          ),
        );
        final fishSynthesis = await FishAudioLiveSpeechSynthesizer(
          apiKey: credential,
          transport: transport,
          model: 's2-pro',
          voice: voice.voiceId,
          latency: FishAudioLatency.low,
          flushAfterCharacters: 48,
        ).synthesizeStream(bufferedDeltas);
        return _FishWithOpenRouterFallback(
          fishSynthesis: fishSynthesis,
          completedText: textCompleted.future,
          synthesizeFallback: _synthesizeWithOpenRouter,
          disableFishAudio: () => _fishAudioUnavailable = true,
        );
      } on FishAudioException {
        // Avoid repeatedly paying connection latency after a credential,
        // entitlement, relay, or provider failure in this runtime.
        _fishAudioUnavailable = true;
      }
    }
    return _BufferedOpenRouterSynthesis(
      textDeltas: textDeltas,
      synthesize: _synthesizeWithOpenRouter,
    );
  }

  Future<AudioTrack> _synthesizeWithOpenRouter(String text) {
    return OpenRouterSpeechSynthesizer.withVoice(
      client: client,
      voice: voice,
    ).synthesize(text);
  }
}

final class _FishWithOpenRouterFallback implements StreamingSpeechSynthesis {
  _FishWithOpenRouterFallback({
    required this.fishSynthesis,
    required this.completedText,
    required this.synthesizeFallback,
    required this.disableFishAudio,
  });

  final StreamingSpeechSynthesis fishSynthesis;
  final Future<String> completedText;
  final Future<AudioTrack> Function(String text) synthesizeFallback;
  final void Function() disableFishAudio;

  @override
  Future<AudioTrack> get completed async {
    try {
      return await fishSynthesis.completed;
    } on FishAudioException {
      disableFishAudio();
      return synthesizeFallback(await completedText);
    }
  }

  @override
  Future<void> cancel() => fishSynthesis.cancel();
}

final class _BufferedOpenRouterSynthesis implements StreamingSpeechSynthesis {
  _BufferedOpenRouterSynthesis({
    required Stream<String> textDeltas,
    required Future<AudioTrack> Function(String text) synthesize,
  }) {
    _subscription = textDeltas.listen(
      _text.write,
      onError: (Object error, StackTrace stackTrace) {
        if (!_completed.isCompleted) {
          _completed.completeError(error, stackTrace);
        }
      },
      onDone: () async {
        if (_completed.isCompleted) return;
        try {
          _completed.complete(await synthesize(_text.toString()));
        } catch (error, stackTrace) {
          _completed.completeError(error, stackTrace);
        }
      },
      cancelOnError: true,
    );
  }

  final StringBuffer _text = StringBuffer();
  final Completer<AudioTrack> _completed = Completer<AudioTrack>();
  late final StreamSubscription<String> _subscription;

  @override
  Future<AudioTrack> get completed => _completed.future;

  @override
  Future<void> cancel() async {
    await _subscription.cancel();
    if (!_completed.isCompleted) {
      _completed.completeError(
        StateError('Streaming speech synthesis was cancelled.'),
      );
    }
  }
}
