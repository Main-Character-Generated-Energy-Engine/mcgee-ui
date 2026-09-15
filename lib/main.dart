import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:narration_engine/narration_engine.dart';
import 'package:narration_engine/openrouter.dart';

import 'audio_output.dart';
import 'capture_store.dart';
import 'film_opening.dart';
import 'fish_audio_key_loader.dart';
import 'fish_audio_transport.dart';
import 'netlify_narration_endpoint.dart';
import 'openrouter_key_loader.dart';
import 'openrouter_runtime.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key, this.home});

  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff8ee6c7),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xff101514),
        useMaterial3: true,
      ),
      home: home ?? const CameraCapturePage(),
    );
  }
}

class CameraCapturePage extends StatefulWidget {
  const CameraCapturePage({super.key, this.ioApiKeyOverride});

  final String? ioApiKeyOverride;

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

enum _ExperienceStage { setup, cameraConsent, opening, live }

class _CameraCapturePageState extends State<CameraCapturePage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  CameraController? _controller;
  late final AnimationController _entryController;
  late final AnimationController _binocularsController;
  late final Animation<double> _previewEntry;
  Timer? _captureTimer;
  StreamSubscription<NarrationEngineEvent>? _narrationEventSubscription;
  CaptureStore? _captureStore;
  FlutterAudioOutput? _audioOutput;
  OpenRouterNarrationRuntime? _narrationRuntime;
  String? _error;
  String? _visibleNarrationPhrase;
  bool _isCapturing = false;
  bool _isInitializingCamera = false;
  bool _isAppActive = true;
  bool _isConnecting = false;
  bool _narrationUnavailable = false;
  bool _hasStartedNarrationAudio = false;
  bool _isNarrationPlaying = false;
  bool _startupLineRequested = false;
  Future<PreparedFilmOpening?>? _openingPreparation;
  FilmOpening? _filmOpening;
  DateTime? _titleVisibleSince;
  int _cameraGeneration = 0;
  _ExperienceStage _experienceStage = _ExperienceStage.setup;
  String? _connectionError;
  String _selectedActor = 'Morgan Freeman';
  NarrationLanguage _selectedLanguage = NarrationLanguage.english;
  AudioPlayer? _switchSoundPlayer;
  Uint8List? _switchSoundBytes;

  static const _actors = <String, OpenRouterVoiceOption>{
    'Morgan Freeman': OpenRouterVoiceOption.morganFreeman,
    'David Attenborough': OpenRouterVoiceOption.davidAttenborough,
    'Eve': OpenRouterVoiceOption.jade,
  };

  static const _actorAvatars = <String, String>{
    'Morgan Freeman': 'lib/assets/morgan-avatar.webp',
    'David Attenborough': 'lib/assets/david-avatar.webp',
    'Eve': 'lib/assets/eve-avatar.webp',
  };

  void _printError(String context, Object error, [StackTrace? stackTrace]) {
    final trace = stackTrace == null ? '' : '\n$stackTrace';
    debugPrint('[MCGEE] $context: $error$trace');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _binocularsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _previewEntry = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.18, 0.75, curve: Curves.easeOutCubic),
    );
    _entryController.forward();
  }

  Future<void> _initializeCamera() async {
    if (_isInitializingCamera) {
      return;
    }
    final generation = ++_cameraGeneration;
    setState(() {
      _isInitializingCamera = true;
      _error = null;
      if (!_startupLineRequested) {
        _experienceStage = _ExperienceStage.opening;
        if (_filmOpening != null) _titleVisibleSince = DateTime.now();
      }
    });
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException(
          'NoCamera',
          'No camera was found on this device.',
        );
      }

      final captureStore = await createCaptureStore();

      final controller = CameraController(
        cameras.first,
        // Medium frames are ample for low-detail model vision and materially
        // reduce capture encoding and upload time on the live path.
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();

      if (!mounted || !_isAppActive || generation != _cameraGeneration) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _captureStore = captureStore;
        _error = null;
      });
      final runtime = _narrationRuntime;
      if (!_startupLineRequested && runtime != null) {
        unawaited(_beginPreparedOpening(runtime, generation));
      } else {
        _revealCamera();
        _startCaptureLoop(captureImmediately: true);
      }
    } on CameraException catch (exception, stackTrace) {
      _printError('Camera initialization failed', exception, stackTrace);
      if (mounted && generation == _cameraGeneration) {
        setState(() {
          _error = exception.description ?? exception.code;
          _experienceStage = _ExperienceStage.cameraConsent;
        });
      }
    } catch (exception, stackTrace) {
      _printError('App initialization failed', exception, stackTrace);
      if (mounted && generation == _cameraGeneration) {
        setState(() {
          _error = exception.toString();
          _experienceStage = _ExperienceStage.cameraConsent;
        });
      }
    } finally {
      if (mounted && generation == _cameraGeneration) {
        setState(() => _isInitializingCamera = false);
      } else if (!mounted) {
        _isInitializingCamera = false;
      }
    }
  }

  void _startCaptureLoop({required bool captureImmediately}) {
    _captureTimer?.cancel();
    if (captureImmediately) {
      _capturePhoto();
    }
    _captureTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _capturePhoto(),
    );
  }

  void _selectActor(String actor) {
    unawaited(_playSwitchSound());
    setState(() => _selectedActor = actor);
    _narrationRuntime?.setVoice(_actors[actor]!);
  }

  Future<void> _playSwitchSound() async {
    try {
      _switchSoundBytes ??= (await rootBundle.load(
        'lib/assets/switch.mp3',
      )).buffer.asUint8List();
      final player = _switchSoundPlayer ??= AudioPlayer();
      await player.stop();
      await player.play(
        BytesSource(_switchSoundBytes!, mimeType: 'audio/mpeg'),
      );
    } catch (error, stackTrace) {
      _printError('Actor switch sound failed', error, stackTrace);
      // Audio feedback is optional; actor selection should still work.
    }
  }

  Future<void> _capturePhoto() async {
    final controller = _controller;
    final captureStore = _captureStore;
    if (controller == null ||
        !controller.value.isInitialized ||
        captureStore == null) {
      return;
    }
    if (_isCapturing || controller.value.isTakingPicture) {
      return;
    }

    _isCapturing = true;
    try {
      final capturedAt = DateTime.now().toUtc();
      final timestamp = capturedAt.millisecondsSinceEpoch ~/ 1000;
      final image = await controller.takePicture();
      final capture = await captureStore.save(
        timestamp: timestamp,
        readBytes: image.readAsBytes,
      );
      unawaited(_narrateCapture(capture, capturedAt));
    } on CameraException catch (exception, stackTrace) {
      _printError('Camera capture failed', exception, stackTrace);
      if (mounted) {
        setState(() => _error = exception.description ?? exception.code);
      }
    } catch (error, stackTrace) {
      _printError('Capture storage failed', error, stackTrace);
    } finally {
      _isCapturing = false;
    }
  }

  Future<void> _narrateCapture(
    StoredCapture capture,
    DateTime capturedAt,
  ) async {
    final runtime = _narrationRuntime;
    if (runtime == null) return;
    try {
      final outcome = await runtime.addCapture(
        capture: capture,
        capturedAt: capturedAt,
      );
      if (!mounted ||
          outcome == null ||
          !identical(runtime, _narrationRuntime)) {
        return;
      }
      if (outcome.kind == NarrationOutcomeKind.spoken &&
          _narrationUnavailable) {
        setState(() => _narrationUnavailable = false);
      } else if (outcome.kind == NarrationOutcomeKind.failed &&
          !_narrationUnavailable) {
        setState(() => _narrationUnavailable = true);
      }
    } catch (error, stackTrace) {
      _printError('Capture narration failed', error, stackTrace);
    }
  }

  Future<void> _connectNarration() async {
    if (_isConnecting) return;
    setState(() {
      _isConnecting = true;
      _connectionError = null;
    });
    try {
      final narrationEndpoint = kIsWeb
          ? defaultNetlifyNarrationEndpoint()
          : null;
      final apiKey = kIsWeb
          ? null
          : widget.ioApiKeyOverride ?? await loadDefaultOpenRouterKey();
      if (!kIsWeb && apiKey == null) {
        throw StateError('Native narration requires .secrets/openrouter-key.');
      }
      String? fishAudioCredential;
      if (!kIsWeb) {
        try {
          fishAudioCredential = fishAudioTransportCredential(
            await loadDefaultFishAudioKey(),
          );
        } catch (error, stackTrace) {
          _printError(
            'Direct Fish Audio configuration unavailable; using OpenRouter TTS',
            error,
            stackTrace,
          );
        }
      }

      final audioOutput = FlutterAudioOutput();
      late final OpenRouterNarrationRuntime runtime;
      try {
        runtime = OpenRouterNarrationRuntime(
          apiKey: apiKey,
          audioOutput: audioOutput,
          voice: _actors[_selectedActor]!,
          language: _selectedLanguage,
          fishAudioCredential: fishAudioCredential,
          fishAudioTransport: fishAudioCredential == null
              ? null
              : createFishAudioTransport(),
          narrationEndpoint: narrationEndpoint,
        );
      } catch (error, stackTrace) {
        _printError('Narration runtime creation failed', error, stackTrace);
        await audioOutput.dispose();
        rethrow;
      }

      final previousRuntime = _narrationRuntime;
      final previousAudioOutput = _audioOutput;
      final previousEventSubscription = _narrationEventSubscription;
      if (!mounted) {
        await runtime.close();
        await audioOutput.dispose();
        return;
      }
      setState(() {
        _narrationRuntime = runtime;
        _audioOutput = audioOutput;
        _narrationUnavailable = false;
        _isNarrationPlaying = false;
        _hasStartedNarrationAudio = false;
        _startupLineRequested = false;
        _filmOpening = null;
        _titleVisibleSince = null;
        _experienceStage = _ExperienceStage.cameraConsent;
      });
      _narrationEventSubscription = runtime.events.listen((event) {
        if (!mounted || !identical(runtime, _narrationRuntime)) return;
        if (event case NarrationFailed(:final error)) {
          _printError('Narration engine failed', error);
          if (!_narrationUnavailable) {
            setState(() => _narrationUnavailable = true);
          }
        }
        if (event is NarrationStarted &&
            _isAppActive &&
            _experienceStage == _ExperienceStage.opening) {
          // The adapter emits this only after audio playback starts.
          _revealCamera();
        }
        final isPlaying = runtime.isPlaying;
        final visiblePhrase = switch (event) {
          NarrationStarted(:final text) => _estimatedSubtitlePhrase(
            text,
            Duration.zero,
            null,
          ),
          NarrationProgress(:final text, :final position, :final duration) =>
            _estimatedSubtitlePhrase(text, position, duration),
          _ => null,
        };
        final soundRecovered =
            event is NarrationStarted && _narrationUnavailable;
        if (_isNarrationPlaying != isPlaying ||
            soundRecovered ||
            (visiblePhrase != null &&
                visiblePhrase != _visibleNarrationPhrase)) {
          setState(() {
            _isNarrationPlaying = isPlaying;
            if (event is NarrationStarted) {
              _hasStartedNarrationAudio = true;
              _narrationUnavailable = false;
            }
            if (visiblePhrase != null) {
              _visibleNarrationPhrase = visiblePhrase;
            }
          });
        }
      });
      // Start the image-free writing request before camera consent/acquisition.
      // Catch immediately: this future may finish long before it is awaited.
      _openingPreparation = _prepareOpening(runtime);
      await previousEventSubscription?.cancel();
      await previousRuntime?.close();
      await previousAudioOutput?.dispose();
      if (mounted &&
          identical(runtime, _narrationRuntime) &&
          _experienceStage == _ExperienceStage.live) {
        _startCaptureLoop(captureImmediately: true);
      }
    } catch (error, stackTrace) {
      _printError('Narration configuration failed', error, stackTrace);
      if (mounted) {
        setState(() {
          _narrationUnavailable = true;
          _connectionError = 'Narration could not connect. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  Future<PreparedFilmOpening?> _prepareOpening(
    OpenRouterNarrationRuntime runtime,
  ) async {
    try {
      return await runtime.prepareOpening(onCredits: (opening) {
        if (!mounted || !identical(runtime, _narrationRuntime)) return;
        setState(() {
          _filmOpening = opening;
          if (_experienceStage == _ExperienceStage.opening && _isAppActive) {
            _titleVisibleSince = DateTime.now();
          }
        });
      });
    } catch (error, stackTrace) {
      _printError('Film opening preparation failed', error, stackTrace);
      return null; // A failed opening must not prevent live narration.
    }
  }

  Future<void> _beginPreparedOpening(
    OpenRouterNarrationRuntime runtime,
    int generation,
  ) async {
    bool isCurrent() =>
        mounted &&
        _isAppActive &&
        generation == _cameraGeneration &&
        identical(runtime, _narrationRuntime) &&
        _experienceStage == _ExperienceStage.opening;

    final prepared = await _openingPreparation;
    if (!isCurrent()) return;
    if (prepared != null) {
      // Give the generated credits a readable beat, including when TTS was
      // already prepared while the user considered camera permission.
      final shownAt = _titleVisibleSince ?? DateTime.now();
      final remaining =
          const Duration(seconds: 3) - DateTime.now().difference(shownAt);
      if (remaining > Duration.zero) await Future<void>.delayed(remaining);
      if (!isCurrent()) return;
      _startupLineRequested = true;
      // Claim playback before submitting a live frame. The engine can then
      // prepare action narration while this cached opening track plays.
      unawaited(_speakOpening(runtime, prepared));
    } else {
      _startupLineRequested = true;
      _revealCamera();
    }
    _startCaptureLoop(captureImmediately: true);
  }

  void _revealCamera() {
    setState(() => _experienceStage = _ExperienceStage.live);
    _entryController.forward(from: 0);
  }

  Future<void> _speakOpening(
    OpenRouterNarrationRuntime runtime,
    PreparedFilmOpening opening,
  ) async {
    try {
      final outcome = await runtime.speakOpening(opening);
      if (outcome.kind == NarrationOutcomeKind.failed) {
        _printError(
          'Opening narration failed',
          outcome.error ?? outcome.reason ?? 'Unknown narration error',
        );
      }
      if (mounted && identical(runtime, _narrationRuntime)) {
        if (_isAppActive && _experienceStage == _ExperienceStage.opening) {
          _revealCamera();
        }
        setState(
          () => _narrationUnavailable =
              outcome.kind == NarrationOutcomeKind.failed &&
              !_hasStartedNarrationAudio,
        );
      }
    } catch (error, stackTrace) {
      _printError('Opening narration failed', error, stackTrace);
      if (mounted && identical(runtime, _narrationRuntime)) {
        if (_isAppActive && _experienceStage == _ExperienceStage.opening) {
          _revealCamera();
        }
        setState(() => _narrationUnavailable = true);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _isAppActive = false;
      _cameraGeneration++;
      _isInitializingCamera = false;
      _titleVisibleSince = null;
      _captureTimer?.cancel();
      final controller = _controller;
      _controller = null;
      if (mounted) {
        setState(() {
          _error = null;
          _isNarrationPlaying = false;
        });
      }
      unawaited(controller?.dispose());
      unawaited(_narrationRuntime?.stop());
    } else if (state == AppLifecycleState.resumed) {
      _isAppActive = true;
      if ((_experienceStage == _ExperienceStage.live ||
              _experienceStage == _ExperienceStage.opening) &&
          _controller == null) {
        unawaited(_initializeCamera());
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _captureTimer?.cancel();
    _entryController.dispose();
    _binocularsController.dispose();
    unawaited(_narrationEventSubscription?.cancel());
    unawaited(_switchSoundPlayer?.dispose());
    _controller?.dispose();
    final narrationRuntime = _narrationRuntime;
    final audioOutput = _audioOutput;
    unawaited(_disposeNarrationResources(narrationRuntime, audioOutput));
    super.dispose();
  }

  Future<void> _disposeNarrationResources(
    OpenRouterNarrationRuntime? runtime,
    FlutterAudioOutput? audioOutput,
  ) async {
    await runtime?.close();
    await audioOutput?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final isReady = controller?.value.isInitialized ?? false;

    return Scaffold(
      appBar: AppBar(toolbarHeight: 0),
      body: switch (_experienceStage) {
        _ExperienceStage.setup => _buildSetupScreen(),
        _ExperienceStage.cameraConsent => _buildCameraConsentScreen(),
        _ExperienceStage.opening => _buildOpeningScreen(),
        _ExperienceStage.live => ColoredBox(
          color: Colors.black,
          child: SafeArea(
            child: Center(
              child: _buildEntryReveal(
                _previewEntry,
                _buildPreview(controller, isReady),
              ),
            ),
          ),
        ),
      },
    );
  }

  Widget _buildOpeningScreen() {
    final opening = _filmOpening;
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              child: opening == null
                  ? const Text(
                      'Preparing your film…',
                      key: ValueKey('opening-preparing'),
                      style: TextStyle(color: Colors.white54, fontSize: 14),
                    )
                  : ConstrainedBox(
                      key: const ValueKey('film-opening-credits'),
                      constraints: const BoxConstraints(maxWidth: 850),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            opening.title,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Georgia',
                              fontSize: MediaQuery.sizeOf(context).width < 600
                                  ? 38
                                  : 64,
                              height: 1.15,
                              letterSpacing: 1.2,
                              color: const Color(0xfff4efe6),
                            ),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            'A film by ${opening.director}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              height: 1.5,
                              letterSpacing: 1.5,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSetupScreen() {
    return _buildOnboardingBackground(
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: 'MCgEe',
            image: true,
            child: Container(
              height: 190,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: const Color(0xfffff8ec),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xffffb04a), width: 2),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Colors.black45,
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: ClipRect(
                  child: Transform.scale(
                    scale: 2.15,
                    child: SvgPicture.asset(
                      'lib/assets/logo.svg',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _buildSetupActorSelector(),
          const SizedBox(height: 24),
          DropdownButtonFormField<NarrationLanguage>(
            key: const ValueKey('narration-language-selector'),
            initialValue: _selectedLanguage,
            decoration: const InputDecoration(
              labelText: 'Narration language',
              prefixIcon: Icon(Icons.language_rounded),
            ),
            items: <DropdownMenuItem<NarrationLanguage>>[
              for (final language in NarrationLanguage.values)
                DropdownMenuItem<NarrationLanguage>(
                  value: language,
                  child: Text(language.nativeName),
                ),
            ],
            onChanged: _isConnecting
                ? null
                : (language) {
                    if (language == null) return;
                    setState(() => _selectedLanguage = language);
                  },
          ),
          if (_connectionError case final error?) ...[
            const SizedBox(height: 16),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xffffa9a9)),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const ValueKey('continue-setup-button'),
            onPressed: _isConnecting ? null : _connectNarration,
            icon: _isConnecting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.arrow_forward_rounded),
            label: Text(_isConnecting ? 'Connecting…' : 'Continue'),
          ),
          if (_controller?.value.isInitialized ?? false) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _isConnecting
                  ? null
                  : () {
                      setState(() => _experienceStage = _ExperienceStage.live);
                      _startCaptureLoop(captureImmediately: false);
                    },
              child: const Text('Back to camera'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCameraConsentScreen() {
    return _buildOnboardingBackground(
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 54),
          const SizedBox(height: 22),
          const Text(
            'Your story is waiting.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w700,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'The lights are ready. $_selectedActor has '
            'cleared their throat. All that remains is you.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.76),
              fontSize: 17,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Allow camera access while this tab is open, and let the ordinary '
            'receive the gravitas it deserves.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.76),
              fontSize: 17,
              height: 1.45,
            ),
          ),
          if (_error case final error?) ...[
            const SizedBox(height: 18),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xffffa9a9)),
            ),
          ],
          const SizedBox(height: 28),
          FilledButton.icon(
            key: const ValueKey('enable-camera-button'),
            onPressed: _isInitializingCamera ? null : _initializeCamera,
            icon: _isInitializingCamera
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.videocam_rounded),
            label: Text(
              _isInitializingCamera
                  ? 'Summoning the camera…'
                  : 'Give me main character energy',
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _isInitializingCamera
                ? null
                : () {
                    setState(() => _experienceStage = _ExperienceStage.setup);
                  },
            child: const Text('Change narrator or language'),
          ),
        ],
      ),
    );
  }

  Widget _buildOnboardingBackground(Widget child) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.35),
          radius: 1.15,
          colors: <Color>[Color(0xff263832), Color(0xff090d0c)],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xff111816).withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white24),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 40,
                      offset: Offset(0, 20),
                    ),
                  ],
                ),
                child: Padding(padding: const EdgeInsets.all(28), child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSetupActorSelector() {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 18,
      runSpacing: 18,
      children: [
        for (final entry in _actors.entries)
          Semantics(
            key: ValueKey('setup-actor-${entry.key}'),
            button: true,
            selected: _selectedActor == entry.key,
            label: 'Choose ${entry.key} as narrator',
            child: InkWell(
              onTap: () => _selectActor(entry.key),
              borderRadius: BorderRadius.circular(50),
              child: SizedBox(
                width: 104,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _selectedActor == entry.key
                              ? const Color(0xff8ee6c7)
                              : Colors.white24,
                          width: _selectedActor == entry.key ? 3 : 1,
                        ),
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          _actorAvatars[entry.key]!,
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      entry.key,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: TextStyle(
                        color: _selectedActor == entry.key
                            ? Colors.white
                            : Colors.white70,
                        fontSize: 12,
                        fontWeight: _selectedActor == entry.key
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEntryReveal(Animation<double> animation, Widget child) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final value = animation.value;
        return Opacity(opacity: value, child: child);
      },
      child: child,
    );
  }

  Widget _buildPreview(CameraController? controller, bool isReady) {
    if (_error != null) {
      return _buildTelevision(
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Camera unavailable\n$_error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    if (!isReady || controller == null) {
      return _buildTelevision(const Center(child: CircularProgressIndicator()));
    }
    return _buildTelevision(
      Stack(
        fit: StackFit.expand,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final previewHeight =
                  constraints.maxWidth / controller.value.aspectRatio;
              return FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: previewHeight,
                  child: CameraPreview(controller),
                ),
              );
            },
          ),
          IgnorePointer(child: CustomPaint(painter: _OldTvEffectPainter())),
          Positioned(
            right: 18,
            bottom: 6,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.72,
                child: SizedBox(
                  width: 140,
                  height: 140,
                  child: SvgPicture.asset(
                    'lib/assets/MCgEe.svg',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
          if (_narrationRuntime != null &&
              !_narrationUnavailable &&
              !_isNarrationPlaying)
            Positioned(
              top: 18,
              left: 18,
              child: IgnorePointer(
                child: Semantics(
                  label: 'Preparing narration',
                  child: RotationTransition(
                    turns: _binocularsController,
                    child: SizedBox(
                      width: 46,
                      height: 46,
                      child: SvgPicture.asset(
                        'binoculars-icon.svg',
                        colorFilter: const ColorFilter.mode(
                          Colors.white,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_visibleNarrationPhrase case final narration?)
            Positioned(
              left: 20,
              right: 20,
              bottom: 18,
              child: AnimatedOpacity(
                opacity: _isNarrationPlaying ? 1 : 0,
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOut,
                child: Text(
                  narration,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    shadows: <Shadow>[
                      Shadow(color: Colors.black, blurRadius: 5),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _estimatedSubtitlePhrase(
    String text,
    Duration position,
    Duration? duration,
  ) {
    final phrases = _splitSubtitlePhrases(text);
    if (phrases.length == 1 || duration == null || duration <= Duration.zero) {
      return phrases.first;
    }

    final totalWeight = phrases.fold<double>(
      0,
      (total, phrase) => total + _subtitlePhraseWeight(phrase),
    );
    final progress = (position.inMicroseconds / duration.inMicroseconds).clamp(
      0.0,
      1.0,
    );
    final targetWeight = totalWeight * progress;
    var elapsedWeight = 0.0;
    for (final phrase in phrases) {
      elapsedWeight += _subtitlePhraseWeight(phrase);
      if (targetWeight < elapsedWeight) return phrase;
    }
    return phrases.last;
  }

  List<String> _splitSubtitlePhrases(String text) {
    final words = text.trim().split(RegExp(r'\s+'));
    final phrases = <String>[];
    var current = <String>[];
    for (final word in words) {
      current.add(word);
      final endsClause = RegExp(r'[,.!?;:\u2013\u2014]$').hasMatch(word);
      if (current.length >= 7 || (current.length >= 4 && endsClause)) {
        phrases.add(current.join(' '));
        current = <String>[];
      }
    }
    if (current.isNotEmpty) {
      if (current.length < 3 && phrases.isNotEmpty) {
        phrases[phrases.length - 1] = '${phrases.last} ${current.join(' ')}';
      } else {
        phrases.add(current.join(' '));
      }
    }
    return phrases.isEmpty ? <String>[text] : phrases;
  }

  double _subtitlePhraseWeight(String phrase) {
    final spokenCharacters = phrase
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .length;
    final pauses = RegExp(r'[,.!?;:\u2013\u2014]').allMatches(phrase).length;
    return spokenCharacters + (pauses * 3.0);
  }

  Widget _buildTelevision(Widget screenContent) {
    return SizedBox.expand(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;
          final framePadding = compact ? 8.0 : 14.0;
          final controlGap = compact ? 6.0 : 10.0;
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xff242424),
                  Color(0xff050505),
                  Color(0xff171717),
                ],
              ),
              border: Border.all(color: Colors.white, width: compact ? 3 : 5),
              borderRadius: BorderRadius.circular(compact ? 10 : 18),
            ),
            child: CustomPaint(
              painter: _TvTexturePainter(),
              child: Padding(
                padding: EdgeInsets.all(framePadding),
                child: Row(
                  children: [
                    Expanded(
                      flex: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(
                            compact ? 10 : 18,
                          ),
                          border: Border.all(
                            color: Colors.white,
                            width: compact ? 4 : 6,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(compact ? 6 : 12),
                          child: screenContent,
                        ),
                      ),
                    ),
                    SizedBox(width: controlGap),
                    Expanded(
                      flex: 2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0xff202020),
                              Colors.black,
                              Color(0xff101010),
                            ],
                          ),
                          border: Border(
                            left: BorderSide(
                              color: Colors.white,
                              width: compact ? 2 : 4,
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            compact ? 5 : 10,
                            compact ? 5 : 10,
                            compact ? 2 : 4,
                            compact ? 5 : 10,
                          ),
                          child: _buildTvControls(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActorSelector() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final avatarSize = constraints.maxWidth < 150 ? 34.0 : 48.0;
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (final actor in _actors.keys)
              Semantics(
                button: true,
                selected: _selectedActor == actor,
                label: 'Choose $actor as narrator',
                child: InkWell(
                  onTap: () => _selectActor(actor),
                  borderRadius: BorderRadius.circular(100),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _selectedActor == actor
                            ? Colors.white
                            : Colors.white30,
                        width: _selectedActor == actor ? 3 : 1,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: avatarSize / 2,
                      backgroundColor: const Color(0xff343c39),
                      backgroundImage: AssetImage(_actorAvatars[actor]!),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildTvControls() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 150;
        final buttonWidth = compact ? constraints.maxWidth * 0.22 : 18.0;
        return Column(
          children: [
            Expanded(flex: 3, child: _buildActorSelector()),
            SizedBox(height: compact ? 6 : 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(
                3,
                (_) => Container(
                  width: buttonWidth,
                  height: compact ? 5 : 8,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
            SizedBox(height: compact ? 7 : 14),
            Expanded(
              flex: 5,
              child: Container(
                margin: EdgeInsets.symmetric(horizontal: compact ? 2 : 6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xff202020),
                      Colors.black,
                      Color(0xff111111),
                    ],
                  ),
                  border: Border.all(
                    color: Colors.white,
                    width: compact ? 2 : 3,
                  ),
                  borderRadius: BorderRadius.circular(100),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black87,
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color: Colors.white12,
                      blurRadius: 2,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: CustomPaint(
                    painter: _SpeakerTexturePainter(),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 5 : 10,
                        vertical: compact ? 10 : 16,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(compact ? 7 : 11, (index) {
                          final isEndLine =
                              index == 0 || index == (compact ? 6 : 10);
                          return FractionallySizedBox(
                            widthFactor: isEndLine ? 0.6 : 1,
                            child: Container(
                              height: compact ? 1 : 2,
                              width: double.infinity,
                              margin: EdgeInsets.symmetric(
                                horizontal: compact ? 3 : 7,
                              ),
                              color: Colors.white,
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SpeakerTexturePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final depthPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xff3b4144),
          Color(0xff151719),
          Color(0xff050607),
          Color(0xff24272a),
        ],
        stops: [0, 0.22, 0.7, 1],
      ).createShader(Offset.zero & size);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(3, 3, size.width - 6, size.height - 6),
        Radius.circular(size.width * 0.42),
      ),
      depthPaint,
    );

    final innerRim = Paint()
      ..color = Colors.white.withValues(alpha: 0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final innerShadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final rimRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(5, 5, size.width - 10, size.height - 10),
      Radius.circular(size.width * 0.42),
    );
    canvas.drawRRect(rimRect, innerShadow);
    canvas.drawRRect(rimRect.deflate(3), innerRim);

    final ribPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = 1;
    final blueRibPaint = Paint()
      ..color = const Color(0xff6e9aa3).withValues(alpha: 0.09)
      ..strokeWidth = 1;
    final bronzeRibPaint = Paint()
      ..color = const Color(0xffb28b68).withValues(alpha: 0.07)
      ..strokeWidth = 1;
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.2)
      ..strokeWidth = 2;
    for (double x = 5; x < size.width; x += 7) {
      final rib = x.toInt() % 21 == 0
          ? blueRibPaint
          : x.toInt() % 28 == 0
          ? bronzeRibPaint
          : ribPaint;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), rib);
    }
    for (double x = 8; x < size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), shadowPaint);
    }

    final dustPaint = Paint()..color = Colors.white.withValues(alpha: 0.1);
    for (double y = 18; y < size.height; y += 31) {
      canvas.drawCircle(Offset(size.width * 0.22, y), 0.7, dustPaint);
      canvas.drawCircle(Offset(size.width * 0.78, y + 9), 0.6, dustPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TvTexturePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final diagonalPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.055)
      ..strokeWidth = 1;
    for (double x = -size.height; x < size.width; x += 9) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        diagonalPaint,
      );
    }

    final speckPaint = Paint()..color = Colors.white.withValues(alpha: 0.075);
    for (double y = 6; y < size.height; y += 18) {
      for (double x = 5; x < size.width; x += 21) {
        canvas.drawCircle(Offset(x, y), 0.8, speckPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _OldTvEffectPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scanlinePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.16)
      ..strokeWidth = 1;
    for (double y = 0; y < size.height; y += 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), scanlinePaint);
    }

    final tintPaint = Paint()
      ..color = const Color(0xffd6b27d).withValues(alpha: 0.04);
    canvas.drawRect(Offset.zero & size, tintPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
