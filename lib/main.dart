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
  late final Animation<double> _previewEntry;
  Timer? _captureTimer;
  Directory? _captureDirectory;
  String? _error;
  int _sceneCount = 0;
  bool _isRecording = false;
  bool _isCapturing = false;
  bool _isInitializingCamera = false;
  bool _isAppActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _previewEntry = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.18, 0.75, curve: Curves.easeOutCubic),
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
        if (_sceneCount == 0) {
          _sceneCount = 1;
        }
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
      setState(() => _isRecording = false);
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
    _entryController.dispose();
    _controller?.dispose();
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
            child: Center(
              child: _buildEntryReveal(
                _previewEntry,
                _buildPreview(controller, isReady),
              ),
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
          Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: CameraPreview(controller),
            ),
          ),
          IgnorePointer(child: CustomPaint(painter: _OldTvEffectPainter())),
          if (!_isRecording)
            const Center(
              child: Icon(Icons.pause_rounded, color: Colors.white70, size: 72),
            ),
        ],
      ),
    );
  }

  Widget _buildTelevision(Widget screenContent) {
    return SizedBox.expand(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xff594238),
          border: Border.all(color: const Color(0xffc28b5e), width: 4),
        ),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Row(
            children: [
              Expanded(
                flex: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xff151b1a),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: const Color(0xff211f1d),
                      width: 10,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black87,
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: screenContent,
                  ),
                ),
              ),
              const SizedBox(width: 22),
              Expanded(flex: 2, child: _buildTvControls()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTvControls() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xff8a5544),
            border: Border.all(color: const Color(0xffd49b66), width: 4),
          ),
          child: const Icon(Icons.power_settings_new, color: Color(0xfff0d0a3)),
        ),
        const SizedBox(height: 28),
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: const Color(0xff302a27),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(
                  7,
                  (_) => Container(
                    height: 2,
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    color: const Color(0xff8c6b57),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
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
