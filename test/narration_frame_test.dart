import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcgee/narration_frame.dart';

void main() {
  Widget frame({
    NarrationFrameStyle style = NarrationFrameStyle.cinema,
    VoidCallback? onEnd,
  }) {
    return MaterialApp(
      home: NarrationFrame(
        style: style,
        feed: const ColoredBox(key: ValueKey('feed'), color: Colors.grey),
        endLabel: 'End story',
        onEnd: onEnd ?? () {},
        caption: 'I remember Ari sat very still.',
        captionVisible: true,
        title: 'The Afternoon Ari Stayed',
        subjectName: 'Ari',
      ),
    );
  }

  Future<void> setSurface(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  test('maps narrators to their genre styles', () {
    expect(
      NarrationFrameStyle.forActor('Morgan Freeman'),
      NarrationFrameStyle.cinema,
    );
    expect(
      NarrationFrameStyle.forActor('David Attenborough'),
      NarrationFrameStyle.documentary,
    );
    expect(NarrationFrameStyle.forActor('Eve'), NarrationFrameStyle.broadcast);
  });

  testWidgets('letterboxes Morgan at 2.39:1 in landscape', (tester) async {
    await setSurface(tester, const Size(1280, 800));
    await tester.pumpWidget(frame());

    final feed = tester.getSize(find.byKey(const ValueKey('feed')));
    expect(feed.width, 1280);
    expect(feed.width / feed.height, closeTo(2.39, 0.01));
  });

  testWidgets('relaxes Morgan to 1.85:1 in portrait', (tester) async {
    await setSurface(tester, const Size(390, 844));
    await tester.pumpWidget(frame());

    final feed = tester.getSize(find.byKey(const ValueKey('feed')));
    expect(feed.width / feed.height, closeTo(1.85, 0.01));
  });

  testWidgets('pillarboxes David at 4:3', (tester) async {
    await setSurface(tester, const Size(1280, 800));
    await tester.pumpWidget(frame(style: NarrationFrameStyle.documentary));

    final feed = tester.getSize(find.byKey(const ValueKey('feed')));
    expect(feed.height, 800);
    expect(feed.width / feed.height, closeTo(4 / 3, 0.01));
    expect(find.text('The Ari'), findsOneWidget);
  });

  testWidgets('shows Eve the headline from the film title', (tester) async {
    await setSurface(tester, const Size(1280, 800));
    await tester.pumpWidget(frame(style: NarrationFrameStyle.broadcast));

    expect(find.text('THE AFTERNOON ARI STAYED'), findsOneWidget);
    expect(find.text('LIVE'), findsOneWidget);
  });

  testWidgets('shows controls only after the mouse moves', (tester) async {
    await setSurface(tester, const Size(1280, 800));
    var ended = 0;
    await tester.pumpWidget(frame(onEnd: () => ended++));

    double controlsOpacity() => tester
        .widget<AnimatedOpacity>(
          find.byKey(const ValueKey('narration-controls')),
        )
        .opacity;

    expect(controlsOpacity(), 0);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(640, 400));
    await mouse.moveTo(const Offset(650, 410));
    await tester.pump();
    expect(controlsOpacity(), 1);

    await tester.tap(find.byKey(const ValueKey('end-experience-button')));
    expect(ended, 1);

    await mouse.moveTo(const Offset(640, 400));
    await tester.pump(NarrationFrame.controlsIdleTimeout);
    expect(controlsOpacity(), 0);
    await mouse.removePointer();
  });

  testWidgets('a tap reveals hidden controls on touch screens', (tester) async {
    await setSurface(tester, const Size(390, 844));
    var ended = 0;
    await tester.pumpWidget(frame(onEnd: () => ended++));

    // The first tap on hidden controls only reveals them.
    await tester.tap(
      find.byKey(const ValueKey('end-experience-button')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(ended, 0);

    await tester.tap(find.byKey(const ValueKey('end-experience-button')));
    expect(ended, 1);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('fades the species card after 10 seconds', (tester) async {
    await setSurface(tester, const Size(1280, 800));
    await tester.pumpWidget(frame(style: NarrationFrameStyle.documentary));

    double cardOpacity() => tester
        .widget<AnimatedOpacity>(
          find
              .ancestor(
                of: find.text('The Ari'),
                matching: find.byType(AnimatedOpacity),
              )
              .first,
        )
        .opacity;

    expect(cardOpacity(), 1);
    await tester.pump(const Duration(seconds: 10));
    expect(cardOpacity(), 0);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('does not show Morgan a title card', (tester) async {
    await setSurface(tester, const Size(1280, 800));
    await tester.pumpWidget(frame());

    expect(find.text('THE AFTERNOON ARI STAYED'), findsNothing);
  });
}
