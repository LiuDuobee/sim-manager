import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sim_manager/features/cards/flip_sim_card.dart';
import 'package:sim_manager/features/globe/topojson.dart';
import 'package:sim_manager/main.dart';
import 'package:sim_manager/pages/home_page.dart';

/// Phone portrait presentation: layout, 48dp touch targets and globe touch
/// gestures. 1080×2400 @ 2.625 is a Pixel 6 class device (≈411×914 dp).
void main() {
  final atlas = decodeWorldAtlas(
      File('assets/geo/countries-110m.json').readAsStringSync());

  Future<void> pumpPhone(WidgetTester tester,
      {Size physical = const Size(1080, 2400), double dpr = 2.625}) async {
    tester.view.physicalSize = physical;
    tester.view.devicePixelRatio = dpr;
    tester.view.padding = FakeViewPadding(top: 63 * dpr / 2.625, bottom: 63);
    tester.view.viewPadding =
        FakeViewPadding(top: 63 * dpr / 2.625, bottom: 63);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        SimVaultApp(home: HomePage(atlasLoader: () async => atlas)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> frames(WidgetTester tester, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  double scrollOffset(WidgetTester tester) => tester
      .state<ScrollableState>(find
          .descendant(
              of: find.byKey(const Key('mobile-scroll')),
              matching: find.byType(Scrollable))
          .first)
      .position
      .pixels;

  String telemetry(WidgetTester tester) => tester
      .widgetList<Text>(find.descendant(
          of: find.byKey(const Key('telemetry')), matching: find.byType(Text)))
      .map((t) => t.data)
      .join(' ');

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('phone uses the dedicated mobile layout, desktop does not',
      (tester) async {
    await pumpPhone(tester);
    expect(find.byKey(const Key('hud-compact')), findsOneWidget);
    expect(find.byKey(const Key('mobile-dock')), findsOneWidget);
    expect(find.byKey(const Key('media-row')), findsOneWidget);
    expect(find.byKey(const Key('country-row')), findsOneWidget);
    expect(find.byKey(const Key('atlas-globe')), findsOneWidget);
    expect(find.byKey(const Key('telemetry')), findsOneWidget);
    expect(find.byKey(const Key('estk-bento')), findsOneWidget);
    expect(find.byType(FlipSimCard), findsNWidgets(5));

    // Single column: every card spans the content width.
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    for (final e in find.byType(FlipSimCard).evaluate()) {
      expect((e.renderObject! as RenderBox).size.width, closeTo(width - 24, 1));
    }
    // Telemetry is moved out of the globe canopy instead of covering it.
    final globe = tester.getRect(find.byKey(const Key('atlas-globe')));
    final tele = tester.getRect(find.byKey(const Key('telemetry')));
    expect(tele.top, greaterThanOrEqualTo(globe.bottom));
    // Content starts below the status bar.
    expect(tester.getTopLeft(find.text('SIMVault')).dy, greaterThan(24));
    // Dock clears the gesture-navigation inset.
    expect(tester.getRect(find.byKey(const Key('mobile-dock'))).bottom,
        lessThanOrEqualTo(914 - 24));

    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    await tester.pump();
    expect(find.byKey(const Key('hud-compact')), findsNothing);
    expect(find.byKey(const Key('mobile-dock')), findsNothing);
  });

  testWidgets('small phone (360dp) lays out without overflow', (tester) async {
    await pumpPhone(tester, physical: const Size(720, 1560), dpr: 2);
    expect(find.byKey(const Key('hud-compact')), findsOneWidget);
    await tester.drag(
        find.byKey(const Key('mobile-scroll')), const Offset(0, -3000));
    await frames(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('interactive controls have >=48dp touch targets on phone',
      (tester) async {
    await pumpPhone(tester);
    const id = 'sim-us-tmobile';
    final keys = [
      'export-all-ics',
      'open-backup',
      'media-all',
      'media-esim',
      'country-all',
      'country-JP',
      'spin-toggle',
      'zoom-in',
      'zoom-out',
      'globe-reset',
      'radar-check-$id',
      'slot-1',
      'slot-15',
      'dock-0',
      'dock-1',
      'dock-2',
      'add-card',
      'checkin-$id',
      'flip-$id',
    ];
    for (final k in keys) {
      final size = tester.getSize(find.byKey(Key(k)));
      expect(size.width, greaterThanOrEqualTo(48), reason: '$k width');
      expect(size.height, greaterThanOrEqualTo(48), reason: '$k height');
    }

    await tester.ensureVisible(find.byKey(const Key('flip-$id')));
    await tester.tap(find.byKey(const Key('flip-$id')));
    await frames(tester, 8);
    for (final k in ['back-checkin', 'ics', 'edit', 'delete', 'unflip']) {
      final size = tester.getSize(find.byKey(Key('$k-$id')));
      expect(size.height, greaterThanOrEqualTo(48), reason: k);
      expect(size.width, greaterThanOrEqualTo(48), reason: k);
    }
  });

  testWidgets('one-finger drag rotates the globe without scrolling the page',
      (tester) async {
    await pumpPhone(tester);
    final before = telemetry(tester);
    await tester.timedDrag(find.byKey(const Key('atlas-globe')),
        const Offset(-160, 120), const Duration(milliseconds: 400));
    await frames(tester, 2);
    expect(scrollOffset(tester), 0);
    expect(telemetry(tester), isNot(before));

    // Dragging outside the globe still scrolls the page.
    await tester.drag(find.text('SIMVault'), const Offset(0, -300));
    await frames(tester, 2);
    expect(scrollOffset(tester), greaterThan(100));
  });

  testWidgets('two-finger pinch zooms the globe within 1.0x-2.0x',
      (tester) async {
    await pumpPhone(tester);
    await tester.tap(find.byKey(const Key('spin-toggle')));
    await tester.pump();
    final c = tester.getCenter(find.byKey(const Key('atlas-globe')));

    Future<void> pinch(double from, double to) async {
      final a = await tester.startGesture(c - Offset(0, from), pointer: 1);
      final b = await tester.startGesture(c + Offset(0, from), pointer: 2);
      await tester.pump();
      for (var i = 1; i <= 10; i++) {
        final d = from + (to - from) * i / 10;
        await a.moveTo(c - Offset(0, d));
        await b.moveTo(c + Offset(0, d));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await a.up();
      await b.up();
      await frames(tester, 2);
    }

    expect(telemetry(tester), contains('1.00x'));
    List<double> center() => RegExp(r'([\d.]+)°[EW] ([\d.]+)°[NS]')
        .firstMatch(telemetry(tester))!
        .groups([1, 2])
        .map((v) => double.parse(v!))
        .toList();
    final before = center();
    await pinch(40, 60); // ×1.5
    expect(telemetry(tester), contains('1.50x'));
    // A symmetric pinch zooms without visibly rotating the globe.
    expect(center()[0], closeTo(before[0], .5));
    expect(center()[1], closeTo(before[1], .5));
    await pinch(30, 150); // far past the limit
    expect(telemetry(tester), contains('2.00x'));
    await pinch(150, 20); // far below the limit
    expect(telemetry(tester), contains('1.00x'));
    expect(scrollOffset(tester), 0);
  });

  testWidgets('dock jumps between sections; matrix and flip work on phone',
      (tester) async {
    await pumpPhone(tester);
    await tester.tap(find.byKey(const Key('dock-2')));
    await frames(tester, 6);
    expect(scrollOffset(tester), greaterThan(900));
    await tester.tap(find.byKey(const Key('dock-1')));
    await frames(tester, 6);
    final atBento = scrollOffset(tester);
    expect(atBento, greaterThan(300));

    await tester.tap(find.byKey(const Key('slot-2')));
    await tester.pump();
    expect(find.textContaining('槽位 #2 已占用 · Club SIM (CSL)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('slot-9')));
    await tester.pump();
    expect(find.byKey(const Key('slot-write')), findsOneWidget);

    await tester.tap(find.byKey(const Key('dock-0')));
    await frames(tester, 6);
    expect(scrollOffset(tester), 0);
  });

  testWidgets('form fields span the phone width and still validate',
      (tester) async {
    await pumpPhone(tester);
    await tester.tap(find.byKey(const Key('add-card')));
    await frames(tester, 8);
    final w = tester.getSize(find.byKey(const Key('field-carrier'))).width;
    expect(w, closeTo(1080 / 2.625 - 32, 1));
    await tester.tap(find.byKey(const Key('save-card')));
    await tester.pump();
    expect(find.text('必填'), findsOneWidget);
  });
}
