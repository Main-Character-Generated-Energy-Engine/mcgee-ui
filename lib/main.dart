import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
  String _selectedActor = 'Morgan Freeman';

  static const _actors = ['Morgan Freeman', 'David Attenborough', 'Jade'];

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
                onTap: () => setState(() => _selectedActor = _actors[index]),
                borderRadius: BorderRadius.circular(100),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _selectedActor == _actors[index]
                          ? Colors.white
                          : Colors.white30,
                      width: _selectedActor == _actors[index] ? 3 : 1,
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
