import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mcgee/narration_engine.dart';
import 'package:mcgee/fish_audio.dart';
import 'package:mcgee/openrouter.dart';

import 'capture_store.dart';
import 'direct_http_speech_synthesizer.dart';
import 'direct_narration_renderer.dart';
import 'film_opening.dart';
import 'narrator_profile.dart';

/// Allows enough time for both multimodal writing and speech synthesis while
/// still preventing old camera frames from entering the live audio stream.
const liveMaximumObservationAge = Duration(seconds: 20);

/// Composition root for the app's narration engine and provider adapters.
final class OpenRouterNarrationRuntime {
  OpenRouterNarrationRuntime._({
    required OpenRouterHttpClient client,
    required NarrationEngine engine,
    required _SelectableSpeechSynthesizer speechSynthesizer,
    required NarrationLanguage language,
    required String characterName,
    required _NarratorSelection narratorSelection,
    DirectHttpSpeechSynthesizer? directHttpSpeech,
  }) : _client = client,
       _engine = engine,
       _speechSynthesizer = speechSynthesizer,
       _language = language,
       _characterName = characterName,
       _narratorSelection = narratorSelection,
       _directHttpSpeech = directHttpSpeech;

  factory OpenRouterNarrationRuntime({
    String? apiKey,
    required AudioOutput audioOutput,
    required String characterName,
    required Map<String, NarratorProfile> narratorProfiles,
    OpenRouterVoiceOption voice = OpenRouterVoiceOption.morganFreeman,
    NarrationLanguage language = NarrationLanguage.english,
    String? fishAudioCredential,
    FishAudioWebSocketTransport? fishAudioTransport,
    NarrativeMemory? memory,
  }) {
    final selection = _NarratorSelection(narratorProfiles, voice);
    final normalizedCharacterName = characterName.trim();
    if (normalizedCharacterName.isEmpty) {
      throw ArgumentError.value(
        characterName,
        'characterName',
        'Must not be empty.',
      );
    }
    final key = apiKey?.trim();
    if (key == null || key.isEmpty || key.contains(RegExp(r'\s'))) {
      throw const FormatException('The selected OpenRouter key is invalid.');
    }
    const mockEndpoint = String.fromEnvironment('OPENROUTER_ENDPOINT');
    final client = OpenRouterHttpClient(
      apiKey: key,
      baseUri: mockEndpoint.isEmpty ? null : Uri.parse(mockEndpoint),
    );
    final random = Random();
    final directHttpSpeech = kIsWeb
        ? DirectHttpSpeechSynthesizer(
            fishApiKey: '',
            voice: voice,
            endpoint: Uri.base.resolve(
              const String.fromEnvironment(
                'SPEECH_ENDPOINT',
                defaultValue: '/api/speech',
              ),
            ),
          )
        : null;
    final speechSynthesizer = _SelectableSpeechSynthesizer(
      voice: voice,
      fishAudioCredential: fishAudioCredential,
      fishAudioTransport: fishAudioTransport,
      directHttpSpeech: directHttpSpeech,
    );
    final narrator = OpenRouterNarrationModel(
      client: client,
      requireSpokenLine: true,
      includeCaptures: true,
      continuous: true,
      maximumWords: 20,
      language: language,
      characterName: normalizedCharacterName,
      narratorInstructions: () => selection.profile.liveInstructions,
    );
    return OpenRouterNarrationRuntime._(
      client: client,
      engine: NarrationEngine(
        // The narration model sees the latest image directly. A local scene
        // marker avoids a second, sequential vision request on the live path.
        sceneInterpreter: const DirectCaptureInterpreter(),
        narrator: narrator,
        speechSynthesizer: speechSynthesizer,
        audioOutput: audioOutput,
        narrationRenderer: kIsWeb
            ? DirectNarrationRenderer(
                narrator: narrator,
                speech: speechSynthesizer,
              )
            : null,
        promptBuilder: ContinuousDocumentaryPromptBuilder(
          maximumWords: 20,
          language: language,
          characterName: normalizedCharacterName,
          narratorInstructions: () => selection.profile.liveInstructions,
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
          openingHandoffMaximumWords: 35,
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
      narratorSelection: selection,
      directHttpSpeech: directHttpSpeech,
    );
  }

  final OpenRouterHttpClient _client;
  final NarrationEngine _engine;
  final _SelectableSpeechSynthesizer _speechSynthesizer;
  final NarrationLanguage _language;
  final String _characterName;
  final _NarratorSelection _narratorSelection;
  int _voiceGeneration = 0;
  int _pendingVoiceSwitches = 0;
  final DirectHttpSpeechSynthesizer? _directHttpSpeech;
  final Set<AudioTrack> _preparedTracks = {};
  bool _closed = false;

  OpenRouterVoiceOption get voice => _narratorSelection.voice;

  Stream<NarrationEngineEvent> get events => _engine.events;
  bool get isPlaying => _engine.isPlaying;
  NarrativeMemorySnapshot get memory => _engine.memory;

  Future<PreparedFilmOpening> prepareOpening({
    required void Function(FilmOpening) onCredits,
  }) async {
    if (_closed) throw StateError('The narration runtime is closed.');
    final generation = _voiceGeneration;
    final opening = await generateFilmOpening(
      _client,
      _language,
      characterName: _characterName,
      profile: _narratorSelection.profile,
    );
    _checkOpeningGeneration(generation);
    onCredits(opening);
    final track = await _speechSynthesizer
        .synthesize(opening.narration)
        .timeout(const Duration(seconds: 20));
    try {
      _checkOpeningGeneration(generation);
    } catch (_) {
      await track.dispose();
      rethrow;
    }
    _preparedTracks.add(track);
    final prepared = PreparedFilmOpening(opening: opening, track: track);
    _preparedOpeningGenerations[prepared] = generation;
    return prepared;
  }

  final Expando<int> _preparedOpeningGenerations = Expando<int>();

  void _checkOpeningGeneration(int generation) {
    if (_closed) throw StateError('The narration runtime is closed.');
    if (generation != _voiceGeneration) {
      throw StateError('The narrator changed while preparing the opening.');
    }
  }

  Future<NarrationOutcome> speakOpening(PreparedFilmOpening opening) {
    if (_closed) throw StateError('The narration runtime is closed.');
    final generation = _preparedOpeningGenerations[opening];
    if (generation == null) {
      throw StateError('Opening belongs to another runtime.');
    }
    _checkOpeningGeneration(generation);
    _preparedTracks.remove(opening.track);
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
    if (_pendingVoiceSwitches > 0) return null;
    final latestCapture = CapturedImage(
      source: 'webcam',
      capturedAt: capturedAt,
      path: capture.path,
      bytes: capture.bytes,
      protagonistHint: 'the recurring foreground camera holder',
    );
    return _engine.submit(<CapturedImage>[latestCapture]);
  }

  Future<void> stop() async {
    await _engine.stop();
    await _directHttpSpeech?.cancelPending();
  }

  Future<void> setVoice(OpenRouterVoiceOption voice) async {
    if (_closed) throw StateError('The narration runtime is closed.');
    _narratorSelection.select(voice);
    _voiceGeneration++;
    _pendingVoiceSwitches++;
    _speechSynthesizer.voice = voice;
    _directHttpSpeech?.voice = voice;
    for (final track in _preparedTracks) {
      unawaited(track.dispose());
    }
    _preparedTracks.clear();
    try {
      // stop invalidates prefetched and in-flight work synchronously.
      await _engine.stop();
      await _directHttpSpeech?.cancelPending();
    } finally {
      _pendingVoiceSwitches--;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _directHttpSpeech?.close();
    for (final track in _preparedTracks) {
      await track.dispose();
    }
    _preparedTracks.clear();
    await _engine.close();
    _client.close();
  }
}

final class _SelectableSpeechSynthesizer implements StreamingSpeechSynthesizer {
  _SelectableSpeechSynthesizer({
    required this.voice,
    required this.fishAudioCredential,
    required this.fishAudioTransport,
    this.directHttpSpeech,
  });

  final String? fishAudioCredential;
  final FishAudioWebSocketTransport? fishAudioTransport;
  final DirectHttpSpeechSynthesizer? directHttpSpeech;
  OpenRouterVoiceOption voice;

  FishAudioLiveSpeechSynthesizer _nativeFish() {
    final credential = fishAudioCredential?.trim();
    final transport = fishAudioTransport;
    if (credential == null || credential.isEmpty || transport == null) {
      throw StateError('Fish Audio must be configured for speech.');
    }
    return FishAudioLiveSpeechSynthesizer(
      apiKey: credential,
      transport: transport,
      model: voice.model,
      voice: voice.voiceId,
      latency: FishAudioLatency.low,
      flushAfterCharacters: 48,
    );
  }

  @override
  Future<AudioTrack> synthesize(String text) {
    if (directHttpSpeech case final direct?) return direct.synthesize(text);
    return _nativeFish().synthesize(text);
  }

  @override
  Future<StreamingSpeechSynthesis> synthesizeStream(Stream<String> textDeltas) {
    return _nativeFish().synthesizeStream(textDeltas);
  }
}

final class _NarratorSelection {
  _NarratorSelection(this.profiles, OpenRouterVoiceOption initialVoice) {
    select(initialVoice);
  }

  final Map<String, NarratorProfile> profiles;
  late OpenRouterVoiceOption voice;
  late NarratorProfile profile;

  void select(OpenRouterVoiceOption nextVoice) {
    final nextProfile = profiles[nextVoice.name];
    if (nextProfile == null) {
      throw ArgumentError.value(
        nextVoice.name,
        'voice',
        'Missing narrator profile.',
      );
    }
    voice = nextVoice;
    profile = nextProfile;
  }
}
