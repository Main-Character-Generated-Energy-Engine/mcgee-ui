import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

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
      home: const CameraCapturePage(),
    );
  }
}

class CameraCapturePage extends StatefulWidget {
  const CameraCapturePage({super.key});

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

class _CameraCapturePageState extends State<CameraCapturePage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  CameraController? _controller;
  late final AnimationController _entryController;
  late final Animation<double> _headerEntry;
  late final Animation<double> _previewEntry;
  late final Animation<double> _controlsEntry;
  Timer? _captureTimer;
  Directory? _captureDirectory;
  String? _error;
  String? _lastCapturePath;
  int _captureCount = 0;
  int _sceneCount = 0;
  bool _isRecording = false;
  bool _isCapturing = false;
  bool _isInitializingCamera = false;
  bool _isAppActive = true;
  Duration _sessionDuration = Duration.zero;
  Timer? _sessionTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _headerEntry = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0, 0.45, curve: Curves.easeOutCubic),
    );
    _previewEntry = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.18, 0.75, curve: Curves.easeOutCubic),
    );
    _controlsEntry = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.42, 1, curve: Curves.easeOutCubic),
    );
    _entryController.forward();
    _initializeCamera();
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

      final captureDirectory = Directory(
        '${Directory.current.path}/captures_webcam',
      );
      await captureDirectory.create(recursive: true);

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
        _captureDirectory = captureDirectory;
        _error = null;
      });
      _entryController.forward(from: 0);
      if (_isRecording) {
        _startCaptureLoop(captureImmediately: true);
      }
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

  void _toggleRecording() {
    if (_isRecording) {
      _captureTimer?.cancel();
      _sessionTimer?.cancel();
      setState(() => _isRecording = false);
      return;
    }

    setState(() {
      _isRecording = true;
      _sceneCount++;
      _sessionDuration = Duration.zero;
    });
    _startCaptureLoop(captureImmediately: true);
  }

  void _startCaptureLoop({required bool captureImmediately}) {
    _captureTimer?.cancel();
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _sessionDuration += const Duration(seconds: 1));
      }
    });
    if (captureImmediately) {
      _capturePhoto();
    }
    _captureTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _capturePhoto(),
    );
  }

  Future<void> _capturePhoto() async {
    final controller = _controller;
    final directory = _captureDirectory;
    if (controller == null ||
        !controller.value.isInitialized ||
        directory == null) {
      return;
    }
    if (_isCapturing || controller.value.isTakingPicture) {
      return;
    }

    _isCapturing = true;
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final image = await controller.takePicture();
      final destination = File('${directory.path}/$timestamp.jpg');
      await File(image.path).copy(destination.path);

      if (mounted) {
        setState(() {
          _captureCount++;
          _lastCapturePath = destination.path;
        });
      }
    } on CameraException catch (exception) {
      if (mounted) {
        setState(() => _error = exception.description ?? exception.code);
      }
    } finally {
      _isCapturing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (Platform.isWindows) {
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _isAppActive = false;
      _captureTimer?.cancel();
      _sessionTimer?.cancel();
      final controller = _controller;
      _controller = null;
      if (mounted) {
        setState(() {
          _error = null;
        });
      }
      unawaited(controller?.dispose());
    } else if (state == AppLifecycleState.resumed) {
      _isAppActive = true;
      _initializeCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _captureTimer?.cancel();
    _sessionTimer?.cancel();
    _entryController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final isReady = controller?.value.isInitialized ?? false;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(toolbarHeight: 0),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildEntryReveal(
                _headerEntry,
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'THE MAIN CHARACTER',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: const Color(0xff8ee6c7),
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Your day,\nframe by frame.',
                            style: theme.textTheme.displaySmall?.copyWith(
                              fontFamily: 'Georgia',
                              fontWeight: FontWeight.w700,
                              height: 0.98,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildSessionBadge(theme),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Expanded(
                child: _buildEntryReveal(
                  _previewEntry,
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: ColoredBox(
                      color: Colors.black,
                      child: _buildPreview(controller, isReady),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildEntryReveal(
                _controlsEntry,
                Row(
                  children: [
                    Expanded(child: _buildStoryStatus(theme)),
                    const SizedBox(width: 18),
                    SizedBox(
                      width: 190,
                      child: FilledButton.icon(
                        onPressed: isReady ? _toggleRecording : null,
                        icon: Icon(
                          _isRecording ? Icons.stop : Icons.play_arrow_rounded,
                        ),
                        label: Text(
                          _isRecording ? 'End scene' : 'Begin my story',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: _isRecording
                              ? const Color(0xffd9624f)
                              : const Color(0xff8ee6c7),
                          foregroundColor: const Color(0xff101514),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Camera unavailable\n$_error',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (!isReady || controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CameraPreview(controller),
            IgnorePointer(
              child: Row(
                children: [
                  Expanded(
                    child: AnimatedSlide(
                      offset: _isRecording
                          ? const Offset(-1.05, 0)
                          : Offset.zero,
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeInOutCubic,
                      child: _buildCurtainPanel(
                        alignment: Alignment.centerRight,
                      ),
                    ),
                  ),
                  Expanded(
                    child: AnimatedSlide(
                      offset: _isRecording
                          ? const Offset(1.05, 0)
                          : Offset.zero,
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeInOutCubic,
                      child: _buildCurtainPanel(
                        alignment: Alignment.centerLeft,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 18,
              left: 18,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  border: Border.all(color: Colors.white24),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Text(
                    _isRecording
                        ? '●  ON AIR  /  SCENE ${_sceneCount.toString().padLeft(2, '0')}'
                        : 'STANDBY  /  SCENE ${_sceneCount.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      color: _isRecording
                          ? const Color(0xffff7766)
                          : Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurtainPanel({required Alignment alignment}) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xff641f27),
            border: Border(
              right: alignment == Alignment.centerRight
                  ? const BorderSide(color: Color(0xffe3b86b), width: 2)
                  : BorderSide.none,
              left: alignment == Alignment.centerLeft
                  ? const BorderSide(color: Color(0xffe3b86b), width: 2)
                  : BorderSide.none,
            ),
          ),
        ),
        Row(
          children: List.generate(
            5,
            (index) => Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border.symmetric(
                    vertical: BorderSide(
                      color: index.isEven ? Colors.white12 : Colors.black26,
                      width: 3,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSessionBadge(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          _formatDuration(_sessionDuration),
          style: theme.textTheme.headlineSmall?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          _isRecording ? 'SCENE IN PROGRESS' : 'SESSION READY',
          style: theme.textTheme.labelSmall?.copyWith(
            color: _isRecording ? const Color(0xffff7766) : Colors.white54,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildStoryStatus(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _isRecording ? 'THE STORY IS HAPPENING' : 'WHEN YOU ARE READY',
          style: theme.textTheme.labelMedium?.copyWith(
            color: _isRecording ? const Color(0xffff7766) : Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          _isRecording
              ? 'Stay in the moment. We are collecting the details.'
              : 'Press begin, then go live your ordinary extraordinary day.',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60),
        ),
        if (_captureCount > 0) ...[
          const SizedBox(height: 5),
          Text(
            '$_captureCount moments collected',
            style: theme.textTheme.labelSmall?.copyWith(
              color: const Color(0xff8ee6c7),
            ),
          ),
          if (_lastCapturePath != null)
            Text(
              'Latest frame: ${_lastCapturePath!.split(Platform.pathSeparator).last}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.white38,
              ),
            ),
        ],
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
