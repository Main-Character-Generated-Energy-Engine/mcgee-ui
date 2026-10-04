import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'app_fonts.dart';

/// The visual grammar of each narrator's genre.
enum NarrationFrameStyle {
  /// Scope widescreen with a warm grade; captions live in the bottom bar.
  cinema,

  /// 4:3 natural-history film with a species card at the start.
  documentary,

  /// 16:9 news broadcast with a live bug, headline and closed captions.
  broadcast;

  static NarrationFrameStyle forActor(String actor) => switch (actor) {
    'David Attenborough' => documentary,
    'Eve' => broadcast,
    _ => cinema,
  };
}

/// Frames the live feed for the selected narrator and hosts the controls,
/// which appear on mouse movement and fade out after a short idle period.
class NarrationFrame extends StatefulWidget {
  const NarrationFrame({
    super.key,
    required this.style,
    required this.feed,
    required this.endLabel,
    required this.onEnd,
    this.caption,
    this.captionVisible = false,
    this.title,
    this.subjectName,
  });

  static const controlsIdleTimeout = Duration(seconds: 3);
  static const speciesCardDuration = Duration(seconds: 10);

  final NarrationFrameStyle style;
  final Widget feed;
  final String endLabel;
  final VoidCallback onEnd;
  final String? caption;
  final bool captionVisible;

  /// The generated film title, shown as Eve's headline.
  final String? title;
  final String? subjectName;

  /// Width-to-height ratio of the picture for [style] in [orientation].
  static double aspectRatioFor(
    NarrationFrameStyle style,
    Orientation orientation,
  ) => switch (style) {
    // 2.39:1 leaves a sliver of picture on a portrait phone.
    NarrationFrameStyle.cinema =>
      orientation == Orientation.portrait ? 1.85 : 2.39,
    NarrationFrameStyle.documentary => 4 / 3,
    NarrationFrameStyle.broadcast => 16 / 9,
  };

  @override
  State<NarrationFrame> createState() => _NarrationFrameState();
}

class _NarrationFrameState extends State<NarrationFrame> {
  static const _cream = Color(0xffefe6d2);
  static const _newsRed = Color(0xffc8102e);
  static const _newsNavy = Color(0xff0b1020);

  // Roughly a 30% sepia blend with a slight contrast lift.
  static const _cinemaGrade = ColorFilter.matrix(<double>[
    0.90, 0.254, 0.063, 0, -12.75, //
    0.115, 0.997, 0.055, 0, -12.75, //
    0.09, 0.176, 0.813, 0, -12.75, //
    0, 0, 0, 1, 0,
  ]);

  // Saturation 1.12 for a slightly richer natural-history look.
  static const _documentaryGrade = ColorFilter.matrix(<double>[
    1.0945, -0.0858, -0.0087, 0, 0, //
    -0.0255, 1.0342, -0.0087, 0, 0, //
    -0.0255, -0.0858, 1.1113, 0, 0, //
    0, 0, 0, 1, 0,
  ]);

  Timer? _idleTimer;
  Timer? _speciesCardTimer;
  bool _controlsVisible = false;
  bool _controlsFocused = false;
  bool _showSpeciesCard = true;

  @override
  void initState() {
    super.initState();
    _speciesCardTimer = Timer(NarrationFrame.speciesCardDuration, () {
      if (mounted) setState(() => _showSpeciesCard = false);
    });
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _speciesCardTimer?.cancel();
    super.dispose();
  }

  void _scheduleHide() {
    _idleTimer?.cancel();
    _idleTimer = Timer(NarrationFrame.controlsIdleTimeout, () {
      if (mounted && !_controlsFocused) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _revealControls() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (_) => _revealControls(),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        // Touch screens have no hover, so a tap stands in for mouse movement.
        onPointerDown: (event) {
          if (event.kind != PointerDeviceKind.mouse) _revealControls();
        },
        child: SizedBox.expand(
          child: ColoredBox(
            color: Colors.black,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.biggest;
                final orientation = size.height > size.width
                    ? Orientation.portrait
                    : Orientation.landscape;
                final ratio = NarrationFrame.aspectRatioFor(
                  widget.style,
                  orientation,
                );
                final frame = _fit(size, ratio);
                final barHeight = (size.height - frame.height) / 2;
                final inBar = barHeight >= _minTextBarHeight;
                return Stack(
                  children: [
                    Center(
                      child: SizedBox.fromSize(
                        size: frame,
                        child: ClipRect(child: _buildPicture(frame, inBar)),
                      ),
                    ),
                    ..._buildBarContent(frame, barHeight, inBar),
                    _buildControls(),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Size _fit(Size space, double ratio) {
    if (space.width / space.height > ratio) {
      return Size(space.height * ratio, space.height);
    }
    return Size(space.width, space.width / ratio);
  }

  double _scale(Size frame) => (frame.width / 900).clamp(0.6, 1.4);

  /// Captions sit in the letterbox bars when they are
  /// tall enough, keeping text off the subject's face; otherwise they
  /// overlay the bottom of the picture.
  static const _minTextBarHeight = 56.0;

  Widget _buildPicture(Size frame, bool captionInBar) {
    final grade = switch (widget.style) {
      NarrationFrameStyle.cinema => _cinemaGrade,
      NarrationFrameStyle.documentary => _documentaryGrade,
      NarrationFrameStyle.broadcast => null,
    };
    final scale = _scale(frame);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (grade == null)
          widget.feed
        else
          ColorFiltered(colorFilter: grade, child: widget.feed),
        if (widget.style != NarrationFrameStyle.broadcast)
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 0.9,
                  colors: [Colors.transparent, Color(0x8c000000)],
                  stops: [0.6, 1],
                ),
              ),
            ),
          ),
        ...switch (widget.style) {
          NarrationFrameStyle.cinema => const <Widget>[],
          NarrationFrameStyle.documentary => _buildDocumentaryOverlay(scale),
          NarrationFrameStyle.broadcast => _buildBroadcastOverlay(
            scale,
            captionInBar ? null : _buildCaption(frame, overlay: true),
          ),
        },
        if (!captionInBar && widget.style != NarrationFrameStyle.broadcast)
          Positioned(
            left: 32 * scale,
            right: 32 * scale,
            bottom: 24 * scale,
            child: _buildCaption(frame, overlay: true),
          ),
      ],
    );
  }

  Widget _buildCaption(Size frame, {required bool overlay}) {
    final scale = _scale(frame);
    const overlayShadows = [
      Shadow(color: Colors.black, blurRadius: 4),
      Shadow(color: Colors.black, blurRadius: 1),
    ];
    final caption = widget.caption ?? '';
    final Widget text = switch (widget.style) {
      NarrationFrameStyle.cinema => Text(
        caption,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: AppFonts.titleFamily,
          fontStyle: FontStyle.italic,
          fontSize: (frame.width / 46).clamp(16.0, 30.0),
          height: 1.2,
          color: _cream,
          shadows: overlay ? overlayShadows : null,
        ),
      ),
      NarrationFrameStyle.documentary => Text(
        caption,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: (18 * scale).clamp(14.0, 24.0),
          height: 1.3,
          shadows: overlay ? overlayShadows : null,
        ),
      ),
      // Closed captions keep their black box in or out of the bar.
      NarrationFrameStyle.broadcast => Container(
        color: Colors.black.withValues(alpha: 0.88),
        padding: EdgeInsets.symmetric(
          horizontal: 12 * scale,
          vertical: 6 * scale,
        ),
        child: Text(
          '>> ${caption.toUpperCase()}',
          style: TextStyle(
            color: Colors.white,
            fontSize: (15 * scale).clamp(12.0, 20.0),
            height: 1.35,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.4,
          ),
        ),
      ),
    };
    return _caption(text);
  }

  List<Widget> _buildBarContent(Size frame, double barHeight, bool inBar) {
    if (!inBar) return const [];
    return [
      Positioned(
        left: 24,
        right: 24,
        bottom: 0,
        height: barHeight,
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(top: (barHeight * 0.18).clamp(10, 32)),
            child: _buildCaption(frame, overlay: false),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildDocumentaryOverlay(double scale) {
    final name = widget.subjectName;
    return [
      Positioned(
        left: 14 * scale,
        top: 12 * scale,
        child: IgnorePointer(child: _logo(44 * scale, opacity: 0.5)),
      ),
      if (name != null)
        Positioned(
          left: 32 * scale,
          bottom: 96 * scale,
          child: AnimatedOpacity(
            opacity: _showSpeciesCard ? 1 : 0,
            duration: const Duration(milliseconds: 900),
            child: _speciesCard(name, scale),
          ),
        ),
    ];
  }

  Widget _speciesCard(String name, double scale) {
    const shadow = [Shadow(color: Color(0x99000000), blurRadius: 3)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Homo sapiens',
          style: TextStyle(
            fontFamily: AppFonts.titleFamily,
            fontStyle: FontStyle.italic,
            fontSize: 22 * scale,
            color: Colors.white,
            shadows: shadow,
          ),
        ),
        Text(
          'The $name',
          style: TextStyle(
            fontSize: 22 * scale,
            fontWeight: FontWeight.w500,
            color: Colors.white,
            shadows: shadow,
          ),
        ),
        SizedBox(height: 2 * scale),
        Text(
          'SPECIMEN UNDER OBSERVATION',
          style: TextStyle(
            fontSize: 11 * scale,
            letterSpacing: 1.6,
            color: Colors.white70,
            shadows: shadow,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildBroadcastOverlay(double scale, Widget? caption) {
    final headline = widget.title ?? 'Developing story';
    return [
      Positioned(
        left: 24 * scale,
        top: 20 * scale,
        child: IgnorePointer(
          child: Row(
            children: [
              Container(
                color: _newsRed,
                padding: EdgeInsets.symmetric(
                  horizontal: 10 * scale,
                  vertical: 5 * scale,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8 * scale,
                      height: 8 * scale,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: 6 * scale),
                    _newsLabel('LIVE', scale),
                  ],
                ),
              ),
              Container(
                color: _newsNavy.withValues(alpha: 0.85),
                padding: EdgeInsets.symmetric(
                  horizontal: 10 * scale,
                  vertical: 5 * scale,
                ),
                child: _newsLabel('MCGEE NEWS', scale),
              ),
            ],
          ),
        ),
      ),
      Positioned(
        left: 24 * scale,
        right: 24 * scale,
        bottom: 24 * scale,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (caption != null)
              Align(
                alignment: Alignment.center,
                child: FractionallySizedBox(widthFactor: 0.78, child: caption),
              ),
            SizedBox(height: 16 * scale),
            Container(
              color: _newsRed,
              padding: EdgeInsets.symmetric(
                horizontal: 10 * scale,
                vertical: 3 * scale,
              ),
              child: _newsLabel('BREAKING', scale, letterSpacing: 2),
            ),
            Container(
              width: double.infinity,
              color: const Color(0xfff4f4f2),
              padding: EdgeInsets.symmetric(
                horizontal: 14 * scale,
                vertical: 7 * scale,
              ),
              child: Text(
                headline.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _newsNavy,
                  fontSize: 26 * scale,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _newsLabel(String text, double scale, {double letterSpacing = 1}) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white,
        fontSize: 13 * scale,
        fontWeight: FontWeight.w700,
        letterSpacing: letterSpacing,
      ),
    );
  }

  Widget _caption(Widget child) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: widget.captionVisible && widget.caption != null ? 1 : 0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
        child: child,
      ),
    );
  }

  Widget _logo(double size, {required double opacity}) {
    return Opacity(
      opacity: opacity,
      child: SizedBox.square(
        dimension: size,
        child: SvgPicture.asset('lib/assets/MCgEe.svg', fit: BoxFit.contain),
      ),
    );
  }

  Widget _buildControls() {
    return Positioned(
      top: 12,
      right: 12,
      child: Focus(
        skipTraversal: true,
        onFocusChange: (focused) {
          _controlsFocused = focused;
          _revealControls();
        },
        child: AnimatedOpacity(
          key: const ValueKey('narration-controls'),
          opacity: _controlsVisible ? 1 : 0,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
          // A tap on hidden controls only reveals them.
          child: IgnorePointer(
            ignoring: !_controlsVisible,
            child: OutlinedButton(
              key: const ValueKey('end-experience-button'),
              onPressed: widget.onEnd,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.black.withValues(alpha: 0.35),
                side: const BorderSide(color: Colors.white38),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
              child: Text(widget.endLabel),
            ),
          ),
        ),
      ),
    );
  }
}
