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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;
          final framePadding = compact ? 8.0 : 14.0;
          final controlGap = compact ? 6.0 : 10.0;
          return DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black,
              border: Border.all(color: Colors.white, width: compact ? 3 : 5),
              borderRadius: BorderRadius.circular(compact ? 10 : 18),
            ),
            child: Padding(
              padding: EdgeInsets.all(framePadding),
              child: Row(
                children: [
                  Expanded(
                    flex: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(compact ? 10 : 18),
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
          );
        },
      ),
    );
  }

  Widget _buildTvControls() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 70;
        final dialSize = compact ? constraints.maxWidth * 0.72 : 58.0;
        final buttonWidth = compact ? constraints.maxWidth * 0.22 : 18.0;
        return Column(
          children: [
            _buildTvDial(0.75, dialSize),
            SizedBox(height: compact ? 6 : 12),
            _buildTvDial(-0.9, dialSize),
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
              child: Container(
                margin: EdgeInsets.symmetric(horizontal: compact ? 2 : 6),
                decoration: BoxDecoration(
                  color: Colors.black,
                  border: Border.all(
                    color: Colors.white,
                    width: compact ? 2 : 3,
                  ),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(
                        compact ? 7 : 11,
                        (_) => Container(
                          height: compact ? 1 : 2,
                          width: double.infinity,
                          margin: EdgeInsets.symmetric(
                            horizontal: compact ? 3 : 7,
                          ),
                          color: Colors.white,
                        ),
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

  Widget _buildTvDial(double angle, double size) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _TvDialPainter(angle)),
    );
  }
}

class _TvDialPainter extends CustomPainter {
  const _TvDialPainter(this.angle);

  final double angle;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final innerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, size.width * 0.47, outerPaint);
    canvas.drawCircle(center, size.width * 0.36, innerPaint);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.drawLine(
      Offset(0, -size.height * 0.27),
      Offset(0, size.height * 0.27),
      outerPaint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TvDialPainter oldDelegate) =>
      oldDelegate.angle != angle;
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
