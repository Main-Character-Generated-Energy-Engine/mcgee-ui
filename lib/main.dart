import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mcgee/narration_engine.dart';
import 'package:mcgee/openrouter.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_fonts.dart';
import 'audio_output.dart';
import 'background_music.dart';
import 'capture_store.dart';
import 'film_opening.dart';
import 'film_opening_credits.dart';
import 'fish_audio_key_loader.dart';
import 'fish_audio_transport.dart';
import 'narration_frame.dart';
import 'narrative_memory_store.dart';
import 'narrator_profile.dart';
import 'openrouter_key_loader.dart';
import 'openrouter_runtime.dart';
import 'user_profile_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppFonts.load();
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
        // Dialogs, form controls, and subtitles use the Material UI face.
        // The film-title view opts into Cormorant separately.
        fontFamily: AppFonts.dialogFamily,
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
  const CameraCapturePage({
    super.key,
    this.ioApiKeyOverride,
    this.userProfileStore,
    this.narrativeMemoryStore,
  });

  final String? ioApiKeyOverride;
  final UserProfileStore? userProfileStore;
  final NarrativeMemoryStore? narrativeMemoryStore;

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

enum _ExperienceStage {
  setup,
  cameraChecking,
  cameraConsent,
  opening,
  live,
}

class _CameraCapturePageState extends State<CameraCapturePage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  CameraController? _controller;
  List<Uint8List>? _mockFrames;
  int _mockFrameIndex = 0;
  bool get _cameraReady =>
      _mockFrames != null || (_controller?.value.isInitialized ?? false);
  late final AnimationController _entryController;
  late final AnimationController _creditsController;
  late final AnimationController _waitingTitlesController;
  late final CurvedAnimation _previewEntry;
  Timer? _captureTimer;
  StreamSubscription<NarrationEngineEvent>? _narrationEventSubscription;
  CaptureStore? _captureStore;
  FlutterAudioOutput? _audioOutput;
  OpenRouterNarrationRuntime? _narrationRuntime;
  String? _error;
  String? _audioError;
  String? _openingPreparationFailure;
  Timer? _openingAudioTimer;
  Timer? _openingWaitingTitlesTimer;
  bool _showWaitingTitles = false;
  DateTime? _titlesFadedAt;
  String? _visibleNarrationPhrase;
  bool _isCapturing = false;
  bool _isInitializingCamera = false;
  bool _cameraAccessDenied = false;
  bool _isAppActive = true;
  bool _isConnecting = false;
  bool _isReturningToSelection = false;
  bool _narrationUnavailable = false;
  bool _hasStartedNarrationAudio = false;
  bool _isNarrationPlaying = false;
  bool _startupLineRequested = false;
  Future<PreparedFilmOpening?>? _openingPreparation;
  FilmOpening? _filmOpening;
  int _cameraGeneration = 0;
  int _actorSelectionGeneration = 0;
  _ExperienceStage _experienceStage = _ExperienceStage.setup;
  String? _connectionError;
  String _selectedActor = 'Morgan Freeman';
  NarrationLanguage _selectedLanguage = NarrationLanguage.english;
  AudioPlayer? _switchSoundPlayer;
  final BackgroundMusic _music = createBackgroundMusic();
  Uint8List? _switchSoundBytes;
  late final UserProfileStore _userProfileStore;
  late final NarrativeMemoryStore _narrativeMemoryStore;
  final TextEditingController _nameController = TextEditingController();
  NarrativeMemory _episodeMemory = NarrativeMemory();
  String? _userName;
  String? _nameError;
  bool _isLoadingProfile = true;
  bool _isSavingProfile = false;
  bool _isEditingName = false;
  bool _showWelcomeBack = false;

  static const _actors = <String, OpenRouterVoiceOption>{
    'Morgan Freeman': OpenRouterVoiceOption.morganFreeman,
    'David Attenborough': OpenRouterVoiceOption.davidAttenborough,
    'Eve': OpenRouterVoiceOption.jade,
  };

  // Kevin MacLeod (incompetech.com), CC BY 4.0; credited on the setup screen.
  static const _actorMusic = <String, String>{
    'Morgan Freeman': 'lib/assets/music/danse-morialta.mp3',
    'David Attenborough': 'lib/assets/music/investigations.mp3',
    'Eve': 'lib/assets/music/stay-the-course.mp3',
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
    _userProfileStore =
        widget.userProfileStore ?? const SharedPreferencesUserProfileStore();
    _narrativeMemoryStore =
        widget.narrativeMemoryStore ?? SharedPreferencesNarrativeMemoryStore();
    WidgetsBinding.instance.addObserver(this);
    _entryController = AnimationController(
      vsync: this,
      duration: FilmOpeningCredits.cameraFadeDuration,
    );
    _creditsController = AnimationController(
      vsync: this,
      duration: FilmOpeningCredits.duration,
    );
    _waitingTitlesController = AnimationController(
      vsync: this,
      duration: OpeningWaitingTitles.duration,
    );
    _creditsController.addStatusListener((status) {
      if (status == AnimationStatus.completed &&
          _experienceStage == _ExperienceStage.opening &&
          !_hasStartedNarrationAudio) {
        _titlesFadedAt = DateTime.now();
        _startOpeningAudioDeadline(_cameraGeneration);
      }
    });
    _previewEntry = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeInOut,
    );
    unawaited(_loadProfile());
  }

  Future<void> _loadProfile() async {
    try {
      final name = await _userProfileStore.loadName();
      final memory = name == null
          ? NarrativeMemory()
          : await _narrativeMemoryStore.load(characterName: name);
      if (!mounted) return;
      setState(() {
        _userName = name;
        _nameController.text = name ?? '';
        _episodeMemory = memory;
        _isEditingName = name == null;
        _showWelcomeBack = name != null;
        _isLoadingProfile = false;
      });
    } catch (error, stackTrace) {
      _printError('Saved profile loading failed', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _isLoadingProfile = false;
        _isEditingName = true;
        _connectionError =
            'Saved details could not be loaded. Enter your name to continue.';
      });
    }
  }

  Future<void> _continueSetup() async {
    if (_isLoadingProfile ||
        _isSavingProfile ||
        _isConnecting ||
        _isReturningToSelection) {
      return;
    }
    late final String name;
    try {
      name = _isEditingName || _userName == null
          ? normalizeCharacterName(_nameController.text)
          : _userName!;
    } on FormatException catch (error) {
      setState(() => _nameError = error.message);
      return;
    }
    // Still inside the Continue tap, so browsers allow audio to start later.
    _music
      ..unlock()
      ..load(_actorMusic[_selectedActor]!);

    setState(() {
      _isSavingProfile = true;
      _nameError = null;
      _connectionError = null;
    });
    try {
      if (name != _userName) {
        await _narrationRuntime?.stop();
        await _narrativeMemoryStore.clear();
        _episodeMemory = NarrativeMemory();
        await _userProfileStore.saveName(name);
      }
      if (!mounted) return;
      setState(() {
        _userName = name;
        _nameController.text = name;
        _isEditingName = false;
        _isSavingProfile = false;
      });
      await _connectNarration();
    } catch (error, stackTrace) {
      _printError('Profile saving failed', error, stackTrace);
      if (mounted) {
        setState(() {
          _connectionError =
              'Your profile could not be prepared. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _isSavingProfile = false);
    }
  }

  Future<void> _initializeCamera() async {
    if (_isInitializingCamera) {
      return;
    }
    final generation = ++_cameraGeneration;
    setState(() {
      _isInitializingCamera = true;
      _error = null;
    });
    try {
      if (const bool.fromEnvironment('MOCK_CAMERA_FEED')) {
        final frames = <Uint8List>[];
        for (var index = 1; index <= 4; index++) {
          final data = await rootBundle.load(
            'test/fixtures/mock-camera-feed/$index.jpg',
          );
          frames.add(data.buffer.asUint8List());
        }
        final captureStore = await createCaptureStore();
        if (!mounted || !_isAppActive || generation != _cameraGeneration) {
          return;
        }
        setState(() {
          _mockFrames = frames;
          _mockFrameIndex = 0;
          _captureStore = captureStore;
          _error = null;
          if (_experienceStage == _ExperienceStage.cameraChecking ||
              _experienceStage == _ExperienceStage.cameraConsent) {
            _experienceStage = _ExperienceStage.opening;
            _creditsController.reset();
            _showWaitingTitles = false;
            if (_filmOpening != null) _audioError = null;
            return;
          }
          if (!_startupLineRequested) {
            _experienceStage = _ExperienceStage.opening;
            _creditsController.reset();
            _showWaitingTitles = false;
            if (_filmOpening != null) _audioError = null;
          }
        });
        _startCreditsIfReady();
        final runtime = _narrationRuntime;
        if (!_startupLineRequested && runtime != null) {
          unawaited(_beginPreparedOpening(runtime, generation));
        } else {
          _revealCamera();
          _startCaptureLoop(captureImmediately: true);
        }
        return;
      }
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
        if (_experienceStage == _ExperienceStage.cameraChecking ||
            _experienceStage == _ExperienceStage.cameraConsent) {
          _experienceStage = _ExperienceStage.opening;
          _creditsController.reset();
          _showWaitingTitles = false;
          if (_filmOpening != null) _audioError = null;
          return;
        }
        if (!_startupLineRequested) {
          // CameraController.initialize completes only after camera access is
          // granted, so credits cannot appear during the permission prompt.
          _experienceStage = _ExperienceStage.opening;
          _creditsController.reset();
          _showWaitingTitles = false;
          if (_filmOpening != null) _audioError = null;
        }
      });
      _startCreditsIfReady();
      final runtime = _narrationRuntime;
      if (!_startupLineRequested && runtime != null) {
        unawaited(_beginPreparedOpening(runtime, generation));
      } else {
        _revealCamera();
        _startCaptureLoop(captureImmediately: true);
      }
    } on CameraException catch (exception, stackTrace) {
      _cancelOpeningWait();
      _printError('Camera initialization failed', exception, stackTrace);
      if (mounted && generation == _cameraGeneration) {
        _creditsController.stop(canceled: true);
        setState(() {
          _error = exception.description ?? exception.code;
          _experienceStage = _ExperienceStage.cameraConsent;
          _cameraAccessDenied = true;
        });
      }
    } catch (exception, stackTrace) {
      _cancelOpeningWait();
      _printError('App initialization failed', exception, stackTrace);
      if (mounted && generation == _cameraGeneration) {
        _creditsController.stop(canceled: true);
        setState(() {
          _error = exception.toString();
          _experienceStage = _ExperienceStage.cameraConsent;
          _cameraAccessDenied = true;
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

  /// Reads the existing grant without causing a browser or system prompt.
  /// Camera initialization is only automatic when the user has already
  /// approved access; otherwise the consent view remains in control.
  Future<void> _checkCameraPermission() async {
    if (const bool.fromEnvironment('MOCK_CAMERA_FEED') ||
        (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows)) {
      await _initializeCamera();
      return;
    }
    try {
      final status = await Permission.camera.status;
      if (!mounted) return;
      if (status.isGranted) {
        await _initializeCamera();
      } else {
        setState(() => _experienceStage = _ExperienceStage.cameraConsent);
        // Let the permission card paint before the browser/system prompt.
        await Future<void>.delayed(Duration.zero);
        if (!mounted || _experienceStage != _ExperienceStage.cameraConsent) {
          return;
        }
        await _requestCameraAccess();
      }
    } catch (error, stackTrace) {
      // Some desktop browsers do not expose the Permissions API. Keep the
      // explicit button available rather than treating that as a denial.
      _printError('Camera permission status check failed', error, stackTrace);
      if (mounted && _experienceStage == _ExperienceStage.cameraChecking) {
        setState(() => _experienceStage = _ExperienceStage.cameraConsent);
      }
    }
  }

  Future<void> _requestCameraAccess() async {
    if (_isInitializingCamera) return;
    if (const bool.fromEnvironment('MOCK_CAMERA_FEED') ||
        (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows)) {
      await _initializeCamera();
      return;
    }
    try {
      final status = await Permission.camera.request();
      if (!mounted) return;
      if (status.isGranted) {
        setState(() => _cameraAccessDenied = false);
        await _initializeCamera();
      } else {
        setState(() {
          _cameraAccessDenied = true;
          _error = null;
        });
      }
    } catch (error, stackTrace) {
      _printError('Camera permission request failed', error, stackTrace);
      if (mounted) {
        setState(() => _cameraAccessDenied = true);
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
    if (actor == _selectedActor) return;
    unawaited(_playSwitchSound());
    setState(() => _selectedActor = actor);
    final revision = ++_actorSelectionGeneration;
    final runtime = _narrationRuntime;
    if (runtime == null) return;
    _captureTimer?.cancel();
    unawaited(_changeNarrator(runtime, actor, revision));
  }

  Future<void> _changeNarrator(
    OpenRouterNarrationRuntime runtime,
    String actor,
    int revision,
  ) async {
    try {
      await runtime.setVoice(_actors[actor]!);
      if (!mounted ||
          !identical(runtime, _narrationRuntime) ||
          revision != _actorSelectionGeneration) {
        return;
      }
      setState(() {
        _isNarrationPlaying = false;
        _visibleNarrationPhrase = null;
      });
      if (!_startupLineRequested) {
        setState(() => _filmOpening = null);
        _creditsController.reset();
        _openingPreparation = _prepareOpening(runtime);
      }
      if (_isAppActive && _experienceStage == _ExperienceStage.live) {
        _startCaptureLoop(captureImmediately: true);
      }
    } catch (error, stackTrace) {
      _printError('Narrator switch failed', error, stackTrace);
      if (mounted && revision == _actorSelectionGeneration) {
        setState(() => _narrationUnavailable = true);
      }
    }
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
    final mockFrames = _mockFrames;
    final captureStore = _captureStore;
    if ((mockFrames == null &&
            (controller == null || !controller.value.isInitialized)) ||
        captureStore == null) {
      return;
    }
    if (_isCapturing || (controller?.value.isTakingPicture ?? false)) {
      return;
    }

    _isCapturing = true;
    try {
      final capturedAt = DateTime.now().toUtc();
      final timestamp = capturedAt.millisecondsSinceEpoch ~/ 1000;
      final Uint8List bytes;
      if (mockFrames != null) {
        bytes = mockFrames[_mockFrameIndex % mockFrames.length];
        if (mounted) setState(() => _mockFrameIndex++);
      } else {
        final image = await controller!.takePicture();
        bytes = await image.readAsBytes();
      }
      final capture = await captureStore.save(
        timestamp: timestamp,
        readBytes: () async => bytes,
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
    final characterName = _userName;
    if (characterName == null) {
      setState(() => _nameError = 'Enter the name the narrator should use.');
      return;
    }
    setState(() {
      _isConnecting = true;
      _connectionError = null;
      _audioError = null;
    });
    _cancelOpeningWait();
    try {
      final apiKey = kIsWeb
          ? const String.fromEnvironment('OPENROUTER_API_KEY')
          : widget.ioApiKeyOverride ?? await loadDefaultOpenRouterKey();
      if (apiKey == null || apiKey.trim().isEmpty) {
        throw StateError(
          kIsWeb
              ? 'Web narration requires OPENROUTER_API_KEY at build time.'
              : 'Native narration requires .secrets/openrouter-key.',
        );
      }
      String? fishAudioCredential;
      if (!kIsWeb) {
        fishAudioCredential = fishAudioTransportCredential(
          await loadDefaultFishAudioKey(),
        );
      }

      final narratorProfiles = await loadNarratorProfiles();
      final audioOutput = FlutterAudioOutput();
      late final OpenRouterNarrationRuntime runtime;
      try {
        runtime = OpenRouterNarrationRuntime(
          apiKey: apiKey,
          audioOutput: audioOutput,
          characterName: characterName,
          narratorProfiles: narratorProfiles,
          voice: _actors[_selectedActor]!,
          language: _selectedLanguage,
          fishAudioCredential: fishAudioCredential,
          fishAudioTransport: kIsWeb ? null : createFishAudioTransport(),
          memory: _episodeMemory,
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
        _startupLineRequested =
            _episodeMemory.snapshot.recentNarrations.isNotEmpty;
        _filmOpening = null;
        _openingPreparationFailure = null;
        _creditsController.reset();
        _showWaitingTitles = false;
        _titlesFadedAt = null;
        _experienceStage = _ExperienceStage.cameraChecking;
        _cameraAccessDenied = false;
      });
      String? loggedVoice;
      _narrationEventSubscription = runtime.events.listen((event) {
        if (!mounted || !identical(runtime, _narrationRuntime)) return;
        if (event case NarrationFailed(:final error)) {
          _printError('Narration engine failed', error);
          setState(() {
            _narrationUnavailable = true;
            if (_experienceStage != _ExperienceStage.opening) {
              _audioError = 'Narration audio failed. Please try again.';
            }
          });
        }
        if (event is NarrationStarted) {
          if (event.captures.isEmpty && _titlesFadedAt != null) {
            final delay = DateTime.now()
                .difference(_titlesFadedAt!)
                .inMilliseconds;
            debugPrint(
              '[MCGEE] Opening playback started $delay ms after titles faded out.',
            );
          }
          if (kDebugMode) {
            final timestamp = event.playbackStartedAt.toUtc().toIso8601String();
            final kind = event.captures.isEmpty ? 'opening' : 'live';
            final line = event.text.replaceAll(RegExp(r'\s+'), ' ').trim();
            final voice = _actors[_selectedActor]!.name;
            final header = loggedVoice != voice || kind == 'opening'
                ? '[narration start][$voice] $timestamp\n'
                : '';
            loggedVoice = voice;
            debugPrint('$header[$kind] [$timestamp]\n$line\n');
          }
          unawaited(
            _narrativeMemoryStore
                .save(characterName: characterName, snapshot: runtime.memory)
                .catchError((error, stackTrace) {
                  _printError('Story memory saving failed', error, stackTrace);
                }),
          );
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
            event is NarrationStarted &&
            (_narrationUnavailable || _audioError != null);
        if (_isNarrationPlaying != isPlaying ||
            soundRecovered ||
            (visiblePhrase != null &&
                visiblePhrase != _visibleNarrationPhrase)) {
          if (_isNarrationPlaying != isPlaying) _music.duck(isPlaying);
          setState(() {
            _isNarrationPlaying = isPlaying;
            if (event is NarrationStarted) {
              _cancelOpeningWait();
              _showWaitingTitles = false;
              _hasStartedNarrationAudio = true;
              _narrationUnavailable = false;
              _audioError = null;
            }
            if (visiblePhrase != null) {
              _visibleNarrationPhrase = visiblePhrase;
            }
          });
        }
      });
      // A restored episode continues directly instead of masking its last beat
      // with a new generic opening. New episodes prepare their opening before
      // camera consent/acquisition.
      _openingPreparation = _startupLineRequested
          ? Future<PreparedFilmOpening?>.value()
          : _prepareOpening(runtime);
      unawaited(_checkCameraPermission());
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
    final revision = _actorSelectionGeneration;
    try {
      return await runtime.prepareOpening(
        onCredits: (opening) {
          if (!mounted ||
              !identical(runtime, _narrationRuntime) ||
              revision != _actorSelectionGeneration) {
            return;
          }
          setState(() {
            _filmOpening = opening;
          });
          _startCreditsIfReady();
        },
      );
    } catch (error, stackTrace) {
      if (revision != _actorSelectionGeneration) return null;
      _printError('Film opening preparation failed', error, stackTrace);
      if (mounted && identical(runtime, _narrationRuntime)) {
        final message = error.toString().contains('HTTP 402')
            ? 'Opening narration is unavailable because the speech service rejected this request. Return to narration selection and try again.'
            : 'Opening narration could not be prepared. Return to narration selection and try again.';
        _openingPreparationFailure = message;
        if (_filmOpening == null ||
            _experienceStage != _ExperienceStage.opening ||
            _audioError != null) {
          setState(() {
            _narrationUnavailable = true;
            _audioError = message;
          });
        }
      }
      return null;
    }
  }

  void _startCreditsIfReady() {
    if (_isAppActive &&
        _cameraReady &&
        _experienceStage == _ExperienceStage.opening &&
        _filmOpening != null &&
        !_creditsController.isAnimating &&
        !_creditsController.isCompleted) {
      _creditsController.forward();
      _music.play();
    }
  }

  Future<void> _beginPreparedOpening(
    OpenRouterNarrationRuntime runtime,
    int generation,
  ) async {
    bool ownsSession() =>
        mounted &&
        _isAppActive &&
        generation == _cameraGeneration &&
        identical(runtime, _narrationRuntime);
    bool isOpening() =>
        ownsSession() && _experienceStage == _ExperienceStage.opening;

    if (!isOpening()) return;
    final prepared = await _openingPreparation;
    if (!isOpening()) return;
    if (_filmOpening != null) {
      try {
        // Credits may already be running while the camera and speech prepare.
        // Finish both cards and return to black before starting the voiceover.
        await _creditsController.forward().orCancel;
      } on TickerCanceled {
        return;
      }
      if (!isOpening()) return;
    }
    if (prepared != null) {
      _startupLineRequested = true;
      // Subscribe before queueing playback. Once NarrationStarted arrives the
      // opening is already in story memory, so the first live frame can safely
      // continue it while the prepared audio is still playing.
      final openingStarted = Completer<void>();
      final openingSubscription = runtime.events.listen((event) {
        if (!openingStarted.isCompleted &&
            event is NarrationStarted &&
            event.captures.isEmpty &&
            event.text == prepared.opening.narration) {
          openingStarted.complete();
        }
      });
      final openingPlayback = _speakOpening(runtime, prepared);
      final audioStarted = await Future.any<bool>(<Future<bool>>[
        openingStarted.future.then((_) => true),
        openingPlayback.then((_) => false),
      ]);
      await openingSubscription.cancel();
      if (!audioStarted && !openingStarted.isCompleted) {
        // A playback failure used to leave the opening on black until the
        // slow-start timer expired. This is most visible when changing voice:
        // surface the failure now instead of silently skipping that narrator's
        // opening.
        if (isOpening()) {
          _showOpeningAudioError(
            _openingPreparationFailure ??
                'Opening narration could not play. Return to narration selection and try again.',
          );
        }
        return;
      }
      _cancelOpeningWait();
      await Future<void>.delayed(const Duration(seconds: 1));
    } else {
      if (_filmOpening == null) {
        _cancelOpeningWait();
        if (isOpening()) {
          _showOpeningAudioError(
            _openingPreparationFailure ??
                'Opening narration could not be prepared. Return to narration selection and try again.',
          );
        }
      }
      return;
    }
    if (!ownsSession()) return;
    _revealCamera();
    _startCaptureLoop(captureImmediately: true);
  }

  void _startOpeningAudioDeadline(int generation) {
    _cancelOpeningWait();
    debugPrint(
      '[MCGEE] Opening titles faded out; extra titles at 5 seconds, audio error at 15 seconds if playback has not started.',
    );
    bool stillWaiting() =>
        mounted &&
        _isAppActive &&
        generation == _cameraGeneration &&
        _experienceStage == _ExperienceStage.opening &&
        !_hasStartedNarrationAudio;
    _openingWaitingTitlesTimer = Timer(const Duration(seconds: 5), () {
      if (!stillWaiting()) return;
      debugPrint(
        '[MCGEE] Opening audio still pending after 5 seconds; showing extra titles.',
      );
      setState(() => _showWaitingTitles = true);
      _waitingTitlesController.forward(from: 0);
    });
    _openingAudioTimer = Timer(const Duration(seconds: 15), () {
      if (!stillWaiting()) return;
      debugPrint(
        '[MCGEE] Opening playback still pending 15 seconds after the titles faded out; speech request remains active.',
      );
      _waitingTitlesController.stop(canceled: true);
      _showOpeningAudioError(
        _openingPreparationFailure ??
            'Opening narration is taking longer than expected. We are still trying to play it. You can wait here or return to narration selection.',
      );
    });
  }

  void _cancelOpeningWait() {
    _openingAudioTimer?.cancel();
    _openingWaitingTitlesTimer?.cancel();
    _waitingTitlesController.stop(canceled: true);
  }

  void _showOpeningAudioError(String message) {
    if (!mounted || _experienceStage != _ExperienceStage.opening) return;
    setState(() {
      _narrationUnavailable = true;
      _audioError = message;
      _showWaitingTitles = false;
    });
  }

  Future<void> _returnToNarrationSelection() async {
    if (_isReturningToSelection || _experienceStage == _ExperienceStage.setup) {
      return;
    }
    _isReturningToSelection = true;
    ++_cameraGeneration;
    ++_actorSelectionGeneration;
    _cancelOpeningWait();
    _captureTimer?.cancel();
    _creditsController.stop(canceled: true);
    _music.stop();
    final runtime = _narrationRuntime;
    final audioOutput = _audioOutput;
    final eventSubscription = _narrationEventSubscription;
    final controller = _controller;
    setState(() {
      _experienceStage = _ExperienceStage.setup;
      _showWelcomeBack = _userName != null;
      _audioError = null;
      _filmOpening = null;
      _openingPreparationFailure = null;
      _titlesFadedAt = null;
      _startupLineRequested = false;
      _hasStartedNarrationAudio = false;
      _showWaitingTitles = false;
      _controller = null;
      _mockFrames = null;
      _captureStore = null;
      // A new selection begins a new session. In particular, do not let an
      // actor tap in setup prepare an opening on the just-ended runtime while
      // the next Continue creates its replacement.
      _narrationRuntime = null;
      _audioOutput = null;
      _narrationEventSubscription = null;
      _openingPreparation = null;
      _isNarrationPlaying = false;
      _visibleNarrationPhrase = null;
    });
    unawaited(controller?.dispose());
    try {
      await eventSubscription?.cancel();
      await runtime?.close();
      await audioOutput?.dispose();
    } catch (error, stackTrace) {
      _printError('Ending narration session failed', error, stackTrace);
    } finally {
      _isReturningToSelection = false;
    }
    debugPrint('[MCGEE] Returned to narration selection from opening.');
  }

  void _revealCamera() {
    _music.play();
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
        if (mounted && identical(runtime, _narrationRuntime)) {
          _openingPreparationFailure =
              'Opening narration could not play. Return to narration selection and try again.';
          if (_audioError != null) {
            _showOpeningAudioError(_openingPreparationFailure!);
          }
        }
      }
      if (mounted && identical(runtime, _narrationRuntime)) {
        setState(
          () => _narrationUnavailable =
              outcome.kind == NarrationOutcomeKind.failed &&
              !_hasStartedNarrationAudio,
        );
      }
    } catch (error, stackTrace) {
      _printError('Opening narration failed', error, stackTrace);
      if (mounted && identical(runtime, _narrationRuntime)) {
        _openingPreparationFailure =
            'Opening narration could not play. Return to narration selection and try again.';
        if (_audioError != null) {
          _showOpeningAudioError(_openingPreparationFailure!);
        }
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
      _creditsController.stop(canceled: true);
      _captureTimer?.cancel();
      _cancelOpeningWait();
      final controller = _controller;
      _controller = null;
      _mockFrames = null;
      if (mounted) {
        setState(() {
          _error = null;
          _isNarrationPlaying = false;
          _showWaitingTitles = false;
        });
      }
      unawaited(controller?.dispose());
      unawaited(_narrationRuntime?.stop());
      _music.stop();
    } else if (state == AppLifecycleState.resumed) {
      _isAppActive = true;
      if ((_experienceStage == _ExperienceStage.live ||
              _experienceStage == _ExperienceStage.opening) &&
          !_cameraReady) {
        unawaited(_initializeCamera());
      }
      if (_experienceStage == _ExperienceStage.live) _music.play();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _captureTimer?.cancel();
    _cancelOpeningWait();
    _previewEntry.dispose();
    _entryController.dispose();
    _creditsController.dispose();
    _waitingTitlesController.dispose();
    _nameController.dispose();
    unawaited(_narrationEventSubscription?.cancel());
    unawaited(_switchSoundPlayer?.dispose());
    unawaited(_music.dispose());
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
    final isReady = _cameraReady;
    final isOnboarding =
        _experienceStage == _ExperienceStage.setup ||
        _experienceStage == _ExperienceStage.cameraChecking ||
        _experienceStage == _ExperienceStage.cameraConsent;

    return Scaffold(
      appBar: AppBar(toolbarHeight: 0),
      body: Stack(
        children: [
          Positioned.fill(
            child: isOnboarding
                ? _buildOnboardingScreen()
                : switch (_experienceStage) {
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
                    // The two onboarding stages are handled above.
                    _ => const SizedBox.shrink(),
                  },
          ),
          if (_audioError case final error?)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: SafeArea(
                child: Material(
                  key: const ValueKey('narration-audio-error'),
                  color: const Color(0xff572c2c),
                  borderRadius: BorderRadius.circular(12),
                  elevation: 8,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          error,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                        if (_experienceStage == _ExperienceStage.opening ||
                            _experienceStage == _ExperienceStage.cameraConsent)
                          TextButton(
                            key: const ValueKey(
                              'return-to-narration-selection',
                            ),
                            onPressed: _returnToNarrationSelection,
                            child: const Text('Back to narration selection'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOpeningScreen() {
    final opening = _filmOpening;
    if (opening == null || !_cameraReady) {
      return const SizedBox.expand(child: ColoredBox(color: Colors.black));
    }
    return DefaultTextStyle.merge(
      style: AppFonts.openingStyle,
      child: _showWaitingTitles
          ? OpeningWaitingTitles(
              titles: switch (_selectedActor) {
                'David Attenborough' => const [
                  'We must preserve our planet’s treasured fauna.\nMade with the generous support of the Save Some Guy Foundation.',
                  'Narrated by David Attenborough.',
                ],
                'Eve' => const [
                  'The following is a recording of the news from that fateful day.',
                  'Viewer discretion is advised.',
                ],
                _ => const ['This film is based on real events.'],
              },
              animation: _waitingTitlesController,
            )
          : FilmOpeningCredits(opening: opening, animation: _creditsController),
    );
  }

  Widget _buildOnboardingScreen() {
    final content = switch (_experienceStage) {
      _ExperienceStage.setup => _buildSetupContent(),
      _ExperienceStage.cameraChecking => _buildCameraCheckingContent(),
      _ExperienceStage.cameraConsent => _buildCameraConsentContent(),
      _ => const SizedBox.shrink(),
    };
    return _buildOnboardingBackground(
      AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutCubic,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          reverseDuration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.98, end: 1).animate(animation),
              child: child,
            ),
          ),
          child: KeyedSubtree(key: ValueKey(_experienceStage), child: content),
        ),
      ),
    );
  }

  Widget _buildSetupContent() {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter): _continueSetup,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _continueSetup,
      },
      child: Focus(
        autofocus: true,
        child: Column(
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
        _buildProtagonistIdentity(),
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
          onPressed: _isConnecting || _isLoadingProfile || _isSavingProfile
              ? null
              : _continueSetup,
          icon: _isConnecting || _isSavingProfile
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.keyboard_return_rounded),
          label: Text(
            _isSavingProfile
                ? 'Saving…'
                : _isConnecting
                ? 'Connecting…'
                : 'Continue',
          ),
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
        const SizedBox(height: 20),
        const Text(
          'Music: “Danse Morialta”, “Investigations”, “Stay the Course” '
          'by Kevin MacLeod (incompetech.com), CC BY 4.0',
          key: ValueKey('music-credits'),
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraCheckingContent() {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 42,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        SizedBox(height: 22),
        Text(
          'Checking camera',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 34,
            fontWeight: FontWeight.w700,
            letterSpacing: -1,
          ),
        ),
      ],
    );
  }

  Widget _buildCameraConsentContent() {
    return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              _cameraAccessDenied
                  ? Icons.sentiment_dissatisfied_rounded
                  : Icons.videocam_rounded,
              color: Colors.white,
              size: 54,
            ),
            const SizedBox(height: 22),
            Text(
              _cameraAccessDenied
                  ? 'We can’t see the scene.'
                  : 'Allow camera access',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w700,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _cameraAccessDenied
                  ? 'Without a camera view, there’s no story to follow. You can try again when you’re ready.'
                  : 'Allow camera access to continue.',
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
          ],
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

  Widget _buildProtagonistIdentity() {
    if (_isLoadingProfile) {
      return const Center(
        child: SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_showWelcomeBack && !_isEditingName && _userName != null) {
      final name = _userName!;
      return Row(
        children: [
          Expanded(
            child: Text(
              'Welcome back, $name.',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            key: const ValueKey('not-you-button'),
            onPressed: _isSavingProfile
                ? null
                : () {
                    setState(() {
                      _showWelcomeBack = false;
                      _userName = null;
                      _nameController.clear();
                      _isEditingName = true;
                      _nameError = null;
                    });
                  },
            child: const Text('Not you?'),
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
          key: const ValueKey('user-name-field'),
          controller: _nameController,
          autofocus: _userName == null,
          enabled: !_isSavingProfile,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          maxLength: 60,
          onChanged: (_) {
            setState(() {
              _isEditingName = true;
              _nameError = null;
            });
          },
          onSubmitted: (_) => _continueSetup(),
          decoration: InputDecoration(
            labelText: 'What is your name?',
            errorText: _nameError,
            prefixIcon: const Icon(Icons.person_outline_rounded),
          ),
          ),
        ),
        // Only offer to forget a name that was actually saved.
        if (_userName != null)
          TextButton(
            key: const ValueKey('not-you-button'),
            onPressed: _isSavingProfile
                ? null
                : () {
                    setState(() {
                      _showWelcomeBack = false;
                      _userName = null;
                      _nameController.clear();
                      _isEditingName = true;
                      _nameError = null;
                    });
                  },
            child: const Text('Not you?'),
          ),
      ],
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
            child: FocusableActionDetector(
              actions: <Type, Action<Intent>>{
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (_) {
                    _selectActor(entry.key);
                    return null;
                  },
                ),
              },
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
    final Widget feed;
    if (_error != null) {
      feed = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Camera unavailable\n$_error',
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else if (_mockFrames case final frames? when frames.isNotEmpty) {
      feed = Image.memory(
        frames[(_mockFrameIndex == 0 ? 0 : _mockFrameIndex - 1) %
            frames.length],
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    } else if (!isReady || controller == null) {
      feed = const Center(child: CircularProgressIndicator());
    } else {
      feed = LayoutBuilder(
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
      );
    }
    return NarrationFrame(
      style: NarrationFrameStyle.forActor(_selectedActor),
      feed: feed,
      caption: _visibleNarrationPhrase,
      captionVisible: _isNarrationPlaying,
      title: _filmOpening?.title,
      subjectName: _userName,
      endLabel: _endExperienceLabel,
      onEnd: _returnToNarrationSelection,
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

  String get _endExperienceLabel => switch (_selectedActor) {
    'David Attenborough' => 'End documentary',
    'Eve' => 'End news cycle',
    _ => 'End story',
  };
}
