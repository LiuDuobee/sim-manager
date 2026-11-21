import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sim_manager/features/cards/brand.dart';
import 'package:sim_manager/features/globe/globe_controller.dart';
import 'package:sim_manager/features/globe/topojson.dart';
import 'package:sim_manager/features/hud/hud_theme.dart';
import 'package:sim_manager/features/hud/motion.dart';
import 'package:sim_manager/main.dart';
import 'package:sim_manager/pages/home_page.dart';
import 'package:sim_manager/services/seed_cards.dart';
import 'package:sim_manager/services/sim_repository.dart';

/// UI polish: hero + summary, countdown ring, brand colours, springs and
/// friction, stamp, card stack, undo bars, empty state, skeleton, a11y.
void main() {
  final atlas = decodeWorldAtlas(
      File('assets/geo/countries-110m.json').readAsStringSync());
  final now = DateTime.now();

  Future<void> frames(WidgetTester tester, [int n = 4]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpApp(WidgetTester tester,
      {bool phone = false,
      double textScale = 1,
      bool reduceMotion = false,
      bool highContrast = false}) async {
    tester.view.physicalSize =
        phone ? const Size(1080, 2400) : const Size(1600, 3000);
    tester.view.devicePixelRatio = phone ? 2.625 : 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(
            disableAnimations: reduceMotion, highContrast: highContrast);
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.pumpWidget(
        SimVaultApp(home: HomePage(atlasLoader: () async => atlas)));
    await tester.pump();
    await frames(tester, 2);
  }

  Future<List<SimCard>> vault() async => SimRepository().load();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('smart summary', () {
    test('counts cards due within 30 days and names the nearest', () {
      expect(smartSummary(buildSeedCards(now), now: now),
          '2 张卡 30 天内到期，最近的是 T-Mobile PayGo · 剩 12 天');
      final far = [
        for (final c in buildSeedCards(now))
          c.copyWith(nextDeadlineDate: addDays(dateOnly(now), 90))
      ];
      expect(smartSummary(far, now: now), startsWith('30 天内没有到期的卡'));
      expect(smartSummary(const []), '还没有卡片');
    });
  });

  group('motion', () {
    test('SpringCurve starts at 0, overshoots a little, lands on 1', () {
      const c = SpringCurve(Motion.flipSpring, .65);
      expect(c.transform(0), 0);
      expect(c.transform(1), 1);
      final peak =
          [for (var i = 1; i < 100; i++) c.transform(i / 100)].reduce(math.max);
      expect(peak, greaterThan(1));
      expect(peak, lessThan(1.15));
    });

    test('a released drag keeps gliding and comes to rest', () {
      final c = GlobeController(centerLon: 0, centerLat: 0, spinning: false);
      c.fling(120, 0);
      expect(c.isFlinging, isTrue);
      c.tick(Duration.zero);
      c.tick(const Duration(milliseconds: 200));
      final early = c.centerLon;
      expect(early, lessThan(0)); // drag right → globe turns west
      for (var ms = 400; ms <= 6000; ms += 200) {
        c.tick(Duration(milliseconds: ms));
      }
      expect(c.isFlinging, isFalse);
      final rest = c.centerLon;
      c.tick(const Duration(milliseconds: 7000));
      expect(c.centerLon, rest);
      expect(rest, lessThan(early));
    });

    test('a new drag or flyTo stops the glide', () {
      final c = GlobeController(spinning: false)..fling(200, 50);
      c.setDragging(true);
      expect(c.isFlinging, isFalse);
      c
        ..setDragging(false)
        ..fling(200, 50)
        ..flyTo(0, 0);
      expect(c.isFlinging, isFalse);
    });

    test('tiny release velocities do not fling', () {
      final c = GlobeController(spinning: false)..fling(5, 5);
      expect(c.isFlinging, isFalse);
    });
  });

  group('brand colours', () {
    test('known carriers get their hue, calibrated per theme', () {
      final tmo = buildSeedCards(now).first;
      final dark = HSLColor.fromColor(brandColor(tmo, HudPalette.dark));
      final light = HSLColor.fromColor(brandColor(tmo, HudPalette.light));
      expect(dark.hue, closeTo(light.hue, 1));
      expect(dark.lightness, greaterThan(light.lightness));
      expect(dark.hue,
          closeTo(HSLColor.fromColor(const Color(0xFFE20074)).hue, 2));
      expect(brandGradient(tmo), isNotNull);
      final unknown = tmo.copyWith(carrierName: 'Zzz', carrierPresetId: '');
      expect(brandGradient(unknown), isNull);
    });
  });

  testWidgets('hero shows the nearest deadline and checks it in',
      (tester) async {
    await pumpApp(tester);
    expect(
        tester.widget<Text>(find.byKey(const Key('hero-days'))).data, '剩 12 天');
    expect(tester.widget<Text>(find.byKey(const Key('smart-summary'))).data,
        contains('最近的是 T-Mobile PayGo'));
    await tester.tap(find.byKey(const Key('hero-checkin')));
    await tester.pump();
    final t = (await vault()).firstWhere((c) => c.id == 'sim-us-tmobile');
    expect(t.daysRemaining(), 30);
    // The nearest card is now CMCC.
    expect(
        tester.widget<Text>(find.byKey(const Key('hero-days'))).data, '剩 26 天');
  });

  testWidgets('countdown ring carries days and tier as text, not only colour',
      (tester) async {
    await pumpApp(tester);
    final ring = find.byKey(const Key('ring-sim-us-tmobile'));
    expect(ring, findsOneWidget);
    expect(
        find.descendant(of: ring, matching: find.text('12')), findsOneWidget);
    expect(
        find.descendant(of: ring, matching: find.text('P1')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('T-Mobile PayGo 剩余 12 天，P1 紧急')),
        findsWidgets);
  });

  testWidgets('check-in drops the 已保号 stamp on the card', (tester) async {
    await pumpApp(tester);
    const id = 'sim-cn-cmcc';
    final stamp = find.descendant(
        of: find.byKey(const Key('stamp-$id')), matching: find.text('已保号'));
    expect(stamp, findsNothing);
    await tester.tap(find.byKey(const Key('checkin-$id')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(stamp, findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(stamp, findsNothing);
  });

  testWidgets('a second tap mid-flip turns the card back (spring)',
      (tester) async {
    await pumpApp(tester);
    const id = 'sim-cn-cmcc';
    await tester.tap(find.byKey(const Key('flip-$id')));
    await tester.pump(const Duration(milliseconds: 60));
    // Still on the front: tap flip again before it passes 90°.
    await tester.tap(find.byKey(const Key('flip-$id')));
    await frames(tester, 10);
    expect(find.byKey(const Key('card-front-$id')), findsOneWidget);
    expect(find.byKey(const Key('card-back-$id')), findsNothing);
  });

  testWidgets('reduced motion flips instantly and skips the glide',
      (tester) async {
    await pumpApp(tester, reduceMotion: true);
    const id = 'sim-cn-cmcc';
    await tester.tap(find.byKey(const Key('flip-$id')));
    await tester.pump();
    expect(find.byKey(const Key('card-back-$id')), findsOneWidget);
  });

  testWidgets('archive and purge undo instead of asking', (tester) async {
    await pumpApp(tester);
    const id = 'sim-gb-giffgaff';
    await tester.tap(find.byKey(const Key('flip-$id')));
    await frames(tester, 7);
    await tester.tap(find.byKey(const Key('delete-$id')));
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    expect((await vault()).any((c) => c.id == id), isFalse);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('undo-archive')));
    await frames(tester, 2);
    final back = (await vault()).firstWhere((c) => c.id == id);
    expect(back.archivedAt, isNull);
    expect(back.events.where((e) => e.type == CardEventType.archive), isEmpty);
    final repo = SimRepository();
    await repo.load();
    expect(await repo.loadArchive(), isEmpty);

    // Archive for real, then purge and undo the purge.
    await tester.ensureVisible(find.byKey(const Key('flip-$id')));
    await tester.tap(find.byKey(const Key('flip-$id')));
    await frames(tester, 7);
    await tester.tap(find.byKey(const Key('delete-$id')));
    await tester.pump(const Duration(seconds: 6));
    await frames(tester, 3);
    await tester.ensureVisible(find.byKey(const Key('archive-toggle')));
    await tester.tap(find.byKey(const Key('archive-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('purge-$id')));
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    tester
        .widget<SnackBarAction>(find.byKey(const Key('undo-purge')))
        .onPressed();
    await frames(tester, 2);
    final again = SimRepository();
    await again.load();
    expect((await again.loadArchive()).single.id, id);
  });

  testWidgets('phone card stack: 56dp strips, tap pulls a card out',
      (tester) async {
    await pumpApp(tester, phone: true);
    await tester.ensureVisible(find.byKey(const Key('vault-mode')));
    await tester.tap(find.byKey(const Key('vault-mode')));
    await frames(tester, 3);
    expect(find.byKey(const Key('card-stack')), findsOneWidget);
    expect(find.byKey(const Key('flip-card-sim-us-tmobile')), findsOneWidget);
    const peek = Key('peek-sim-hk-clubsim');
    expect(tester.getSize(find.byKey(peek)).height, 56);
    expect(find.byKey(const Key('flip-card-sim-hk-clubsim')), findsNothing);
    await tester.ensureVisible(find.byKey(peek));
    await tester.tap(find.byKey(peek));
    await frames(tester, 6);
    expect(find.byKey(const Key('flip-card-sim-hk-clubsim')), findsOneWidget);
    expect(find.byKey(const Key('peek-sim-us-tmobile')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty vault guides the first run; samples load in one tap',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      SimRepository.storageKey: SimCard.encodeList([]),
      SimRepository.seededKey: true,
    });
    await pumpApp(tester);
    expect(find.byKey(const Key('empty-vault')), findsOneWidget);
    expect(find.byKey(const Key('hero')), findsNothing);
    for (final k in ['empty-add', 'empty-import', 'empty-samples']) {
      expect(find.byKey(Key(k)), findsOneWidget);
    }
    await tester.ensureVisible(find.byKey(const Key('empty-samples')));
    await tester.tap(find.byKey(const Key('empty-samples')));
    await frames(tester, 2);
    expect((await vault()).length, 5);
    expect(find.byKey(const Key('hero')), findsOneWidget);
  });

  testWidgets('skeleton shows while the vault loads', (tester) async {
    tester.view.physicalSize = const Size(1600, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        SimVaultApp(home: HomePage(atlasLoader: () async => atlas)));
    expect(find.byKey(const Key('skeleton')), findsOneWidget);
    await tester.pump();
    await frames(tester, 2);
    expect(find.byKey(const Key('skeleton')), findsNothing);
  });

  testWidgets('high contrast makes every glass pane solid', (tester) async {
    await pumpApp(tester, highContrast: true);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('form error shakes and keeps the page', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('add-card')));
    await frames(tester, 5);
    await tester.tap(find.byKey(const Key('save-card')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final shake = tester
        .widgetList<Transform>(find.ancestor(
            of: find.byType(Form), matching: find.byType(Transform)))
        .first;
    expect(shake.transform.getTranslation().x, isNot(0));
    await frames(tester, 5);
    expect(find.text('必填'), findsOneWidget);
  });

  for (final width in [1080.0, 945.0]) {
    testWidgets(
        'phone layout survives 1.3× text (${(width / 2.625).round()}dp)',
        (tester) async {
      tester.view.physicalSize = Size(width, 2400);
      tester.view.devicePixelRatio = 2.625;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await tester.pumpWidget(
          SimVaultApp(home: HomePage(atlasLoader: () async => atlas)));
      await tester.pump();
      await frames(tester, 2);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('dock-2')));
      await frames(tester, 6);
      await tester.tap(find.byKey(const Key('flip-sim-us-tmobile')));
      await frames(tester, 8);
      expect(tester.takeException(), isNull);
    });
  }
}
