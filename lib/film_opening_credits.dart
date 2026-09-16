import 'package:flutter/material.dart';

import 'film_opening.dart';

/// Two separate cards with true black between them and after the final credit.
class FilmOpeningCredits extends StatelessWidget {
  const FilmOpeningCredits({
    super.key,
    required this.opening,
    required this.animation,
  });

  static const duration = Duration(milliseconds: 9000);
  static const cameraFadeDuration = Duration(milliseconds: 3000);

  final FilmOpening opening;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final titleSize = (width * 0.085).clamp(32.0, 76.0).toDouble();
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: AnimatedBuilder(
                animation: animation,
                builder: (context, _) {
                  final ms = animation.value * duration.inMilliseconds;
                  final titleOpacity = _opacity(ms, 0, 1200, 3000, 4000);
                  final directorOpacity = _opacity(ms, 4600, 5800, 7600, 8600);
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      Opacity(
                        key: const ValueKey('film-title-fade'),
                        opacity: titleOpacity,
                        child: Text(
                          opening.title.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: titleSize,
                            height: 1.15,
                            fontWeight: FontWeight.w400,
                            letterSpacing: titleSize * 0.07,
                            color: const Color(0xffeee9dd),
                          ),
                        ),
                      ),
                      Opacity(
                        key: const ValueKey('film-director-fade'),
                        opacity: directorOpacity,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'A FILM BY',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Roboto',
                                fontSize: 10,
                                height: 1.6,
                                letterSpacing: 4,
                                fontWeight: FontWeight.w400,
                                color: Color(0xffb9b4aa),
                              ),
                            ),
                            const SizedBox(height: 22),
                            Text(
                              opening.director,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: (width * 0.05).clamp(26.0, 42.0).toDouble(),
                                height: 1.25,
                                fontWeight: FontWeight.w400,
                                letterSpacing: 1.5,
                                color: const Color(0xffeee9dd),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  static double _opacity(
    double ms,
    double start,
    double fullyVisible,
    double fadeOut,
    double end,
  ) {
    if (ms <= start || ms >= end) return 0;
    if (ms < fullyVisible) {
      return Curves.easeInOut.transform((ms - start) / (fullyVisible - start));
    }
    if (ms <= fadeOut) return 1;
    return 1 - Curves.easeInOut.transform((ms - fadeOut) / (end - fadeOut));
  }
}
