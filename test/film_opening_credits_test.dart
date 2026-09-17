import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcgee/film_opening.dart';
import 'package:mcgee/film_opening_credits.dart';

void main() {
  testWidgets('title and director fade separately through black', (
    tester,
  ) async {
    final controller = AnimationController(
      vsync: tester,
      duration: FilmOpeningCredits.duration,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: FilmOpeningCredits(
          opening: const FilmOpening(
            title: 'One More Excuse',
            director: 'Leon Varrin',
            narration: 'An opening.',
          ),
          animation: controller,
        ),
      ),
    );
    double opacity(String key) =>
        tester.widget<Opacity>(find.byKey(ValueKey(key))).opacity;
    Future<void> at(int ms, double title, double director) async {
      controller.value = ms / FilmOpeningCredits.duration.inMilliseconds;
      await tester.pump();
      expect(opacity('film-title-fade'), closeTo(title, 0.01));
      expect(opacity('film-director-fade'), closeTo(director, 0.01));
    }

    await at(0, 0, 0);
    await at(600, 0.5, 0);
    await at(2000, 1, 0);
    await at(3500, 0.5, 0);
    await at(4300, 0, 0);
    await at(5200, 0, 0.5);
    await at(6600, 0, 1);
    await at(8100, 0, 0.5);
    await at(8800, 0, 0);
    await at(9000, 0, 0);
    expect(
      FilmOpeningCredits.cameraFadeDuration,
      const Duration(milliseconds: 3000),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('extra opening titles fade in sequence and end on black', (
    tester,
  ) async {
    final controller = AnimationController(
      vsync: tester,
      duration: OpeningWaitingTitles.duration,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: OpeningWaitingTitles(
          titles: const ['First title', 'Second title'],
          animation: controller,
        ),
      ),
    );
    double opacity(int index) => tester
        .widget<Opacity>(find.byKey(ValueKey('opening-waiting-title-$index')))
        .opacity;
    Future<void> at(int seconds, double first, double second) async {
      controller.value = seconds / 10;
      await tester.pump();
      expect(opacity(0), closeTo(first, 0.01));
      expect(opacity(1), closeTo(second, 0.01));
    }

    await at(0, 0, 0);
    await at(2, 1, 0);
    await at(5, 0, 0);
    await at(7, 0, 1);
    await at(10, 0, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
