import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:narration_engine/narration_engine.dart';
import 'package:narration_engine/openrouter.dart';
import 'package:win32/win32.dart';

import 'audio_output.dart';
import 'capture_store.dart';
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
  const CameraCapturePage({super.key});

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

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
  String? _lastNarration;
  bool _isRecording = false;
  bool _isCapturing = false;
  bool _isInitializingCamera = false;
  bool _isAppActive = true;
  bool _isSelectingKey = false;
  bool _narrationUnavailable = false;
  bool _isNarrationPlaying = false;
  String _selectedActor = 'Morgan Freeman';
  File? _switchSoundFile;

  static const _actors = <String, OpenRouterVoiceOption>{
    'Morgan Freeman': OpenRouterVoiceOption.morganFreeman,
    'David Attenborough': OpenRouterVoiceOption.davidAttenborough,
    'Jade': OpenRouterVoiceOption.jade,
  };

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
    _initializeCamera();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_configureOpenRouterKey(tryDefaultFile: true));
    });
  }

  Future<void> _initializeCamera() async {
    if (_isInitializingCamera) {
      return;
    }
    _isInitializingCamera = true;
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
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();

      if (!mounted || !_isAppActive) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _captureStore = captureStore;
        _error = null;
        _isRecording = true;
      });
      _entryController.forward(from: 0);
      _startCaptureLoop(captureImmediately: true);
    } on CameraException catch (exception) {
      if (mounted) {
        setState(() {
          _error = exception.description ?? exception.code;
        });
      }
    } catch (exception) {
      if (mounted) {
        setState(() {
          _error = exception.toString();
        });
      }
    } finally {
      _isInitializingCamera = false;
    }
  }

  void _togglePause() {
    if (_isRecording) {
      _captureTimer?.cancel();
      unawaited(_narrationRuntime?.stop());
      setState(() {
        _isRecording = false;
        _isNarrationPlaying = false;
      });
      return;
    }

    setState(() => _isRecording = true);
    _startCaptureLoop(captureImmediately: true);
  }

  void _startCaptureLoop({required bool captureImmediately}) {
    _captureTimer?.cancel();
    if (captureImmediately) {
      _capturePhoto();
    }
    _captureTimer = Timer.periodic(
      const Duration(seconds: 5),
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
      if (!Platform.isWindows) {
        await SystemSound.play(SystemSoundType.click);
        return;
      }
      _switchSoundFile ??= await _prepareSwitchSound();
      const alias = 'mcgee_switch_sound';
      _sendMci('close $alias');
      final path = _switchSoundFile!.path.replaceAll('"', '');
      _sendMci('open "$path" type mpegvideo alias $alias');
      _sendMci('play $alias');
    } catch (_) {
      // Audio feedback is optional; actor selection should still work.
    }
  }

  Future<File> _prepareSwitchSound() async {
    final bytes = (await rootBundle.load(
      'lib/assets/switch.mp3',
    )).buffer.asUint8List();
    final file = File('${Directory.systemTemp.path}/mcgee_switch.mp3');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  void _sendMci(String command) {
    final nativeCommand = command.toNativeUtf16();
    try {
      mciSendString(PCWSTR(nativeCommand), null, 0, null);
    } finally {
      calloc.free(nativeCommand);
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
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final image = await controller.takePicture();
      final capture = await captureStore.save(
        timestamp: timestamp,
        sourcePath: image.path,
        readBytes: image.readAsBytes,
      );
      final capturedAt = DateTime.fromMillisecondsSinceEpoch(
        timestamp * 1000,
        isUtc: true,
      );
      unawaited(_narrateCapture(capture, capturedAt));
    } on CameraException catch (exception) {
      if (mounted) {
        setState(() => _error = exception.description ?? exception.code);
      }
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
      setState(() {
        _narrationUnavailable = outcome.kind == NarrationOutcomeKind.failed;
        if (outcome.kind == NarrationOutcomeKind.spoken) {
          _lastNarration = outcome.text;
        }
      });
    } catch (_) {
      if (mounted && identical(runtime, _narrationRuntime)) {
        setState(() => _narrationUnavailable = true);
      }
    }
  }

  Future<void> _configureOpenRouterKey({required bool tryDefaultFile}) async {
    if (_isSelectingKey) return;
    setState(() => _isSelectingKey = true);
    try {
      String? key;
      String? fallbackMessage;
      if (tryDefaultFile) {
        try {
          key = await loadDefaultOpenRouterKey();
        } catch (_) {
          fallbackMessage =
              'The key in .secrets/openrouter-key could not be used.';
        }
      }
      if (!mounted) return;
      key ??= await _showOpenRouterKeyDialog(message: fallbackMessage);
      if (key == null || !mounted) return;

      final audioOutput = FlutterAudioOutput();
      late final OpenRouterNarrationRuntime runtime;
      try {
        runtime = OpenRouterNarrationRuntime(
          apiKey: key,
          audioOutput: audioOutput,
          voice: _actors[_selectedActor]!,
        );
      } catch (_) {
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
      });
      _narrationEventSubscription = runtime.events.listen((event) {
        if (!mounted || !identical(runtime, _narrationRuntime)) return;
        final isPlaying = runtime.isPlaying;
        final startedNarration = switch (event) {
          NarrationStarted(:final text) => text,
          _ => null,
        };
        if (_isNarrationPlaying != isPlaying || startedNarration != null) {
          setState(() {
            _isNarrationPlaying = isPlaying;
            if (startedNarration != null) {
              _lastNarration = startedNarration;
            }
          });
        }
      });
      await previousEventSubscription?.cancel();
      await previousRuntime?.close();
      await previousAudioOutput?.dispose();
    } catch (_) {
      if (mounted) setState(() => _narrationUnavailable = true);
    } finally {
      if (mounted) setState(() => _isSelectingKey = false);
    }
  }

  Future<String?> _showOpenRouterKeyDialog({String? message}) async {
    final formKey = GlobalKey<FormState>();
    var key = '';
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Connect OpenRouter'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message != null) ...[
                  Text(message),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  autofocus: true,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.visiblePassword,
                  onChanged: (value) => key = value,
                  decoration: const InputDecoration(
                    labelText: 'OpenRouter API key',
                    hintText: 'Paste your OpenRouter key here',
                  ),
                  validator: (value) {
                    final key = value?.trim() ?? '';
                    if (key.isEmpty) return 'Paste your OpenRouter key.';
                    if (key.contains(RegExp(r'\s'))) {
                      return 'The key cannot contain whitespace.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                const Text('The key is kept in memory only and is not stored.'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.pop(dialogContext, key.trim());
                }
              },
              child: const Text('Connect'),
            ),
          ],
        );
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _isAppActive = false;
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
      _initializeCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _captureTimer?.cancel();
    _entryController.dispose();
    _binocularsController.dispose();
    unawaited(_narrationEventSubscription?.cancel());
    _controller?.dispose();
    final narrationRuntime = _narrationRuntime;
    final audioOutput = _audioOutput;
    unawaited(
      Future<void>(() async {
        await narrationRuntime?.close();
        await audioOutput?.dispose();
      }),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final isReady = controller?.value.isInitialized ?? false;

    return Scaffold(
      appBar: AppBar(toolbarHeight: 0),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: isReady ? _togglePause : null,
        child: ColoredBox(
          color: Colors.black,
          child: SafeArea(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: _buildEntryReveal(
                    _previewEntry,
                    _buildPreview(controller, isReady),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: FilledButton.tonalIcon(
                    onPressed: _isSelectingKey
                        ? null
                        : () => _configureOpenRouterKey(tryDefaultFile: false),
                    icon: Icon(
                      _narrationRuntime == null
                          ? Icons.key_rounded
                          : _narrationUnavailable
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                    ),
                    label: Text(
                      _isSelectingKey
                          ? 'Connecting…'
                          : _narrationRuntime == null
                          ? 'Enter key'
                          : 'Narrator ready',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEntryReveal(Animation<double> animation, Widget child) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final value = animation.value;
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - value)),
            child: child,
          ),
        );
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
          if (!_isRecording)
            const Center(
              child: Icon(Icons.pause_rounded, color: Colors.white70, size: 72),
            ),
          if (_isRecording &&
              _narrationRuntime != null &&
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
          if (_lastNarration case final narration?)
            Positioned(
              left: 20,
              right: 20,
              bottom: 18,
              child: Text(
                narration,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  shadows: <Shadow>[Shadow(color: Colors.black, blurRadius: 5)],
                ),
              ),
            ),
        ],
      ),
    );
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
        const avatarIcons = [Icons.person, Icons.person, Icons.person];
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var index = 0; index < _actors.length; index++)
              InkWell(
                onTap: () => _selectActor(_actors.keys.elementAt(index)),
                borderRadius: BorderRadius.circular(100),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _selectedActor == _actors.keys.elementAt(index)
                          ? Colors.white
                          : Colors.white30,
                      width: _selectedActor == _actors.keys.elementAt(index)
                          ? 3
                          : 1,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: avatarSize / 2,
                    backgroundColor: index == 0
                        ? const Color(0xff6d7880)
                        : index == 1
                        ? const Color(0xff8b6d57)
                        : const Color(0xff8c5570),
                    child: Icon(
                      avatarIcons[index],
                      color: Colors.white,
                      size: avatarSize * 0.62,
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
