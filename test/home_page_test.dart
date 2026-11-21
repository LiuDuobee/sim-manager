import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sim_manager/features/cards/flip_sim_card.dart';
import 'package:sim_manager/features/globe/globe_controller.dart';
import 'package:sim_manager/features/globe/topojson.dart';
import 'package:sim_manager/features/hud/hud_stage.dart';
import 'package:sim_manager/main.dart';
import 'package:sim_manager/pages/home_page.dart';
import 'package:sim_manager/services/sim_repository.dart';

void main() {
  final atlas = decodeWorldAtlas(
      File('assets/geo/countries-110m.json').readAsStringSync());

  Future<({ByteData rgba, int width, int height})> screenPixels(
      WidgetTester tester) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find
        .ancestor(
            of: find.byType(HudStage), matching: find.byType(RepaintBoundary))
        .last);
    expect(boundary.localToGlobal(Offset.zero), Offset.zero);
    return (await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return (rgba: data!, width: image.width, height: image.height);
    }))!;
  }

  Future<void> pumpHome(WidgetTester tester, {SimRepository? repo}) async {
    tester.view.physicalSize = const Size(1600, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(SimVaultApp(
        home: HomePage(repository: repo, atlasLoader: () async => atlas)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<List<SimCard>> stored() async => SimRepository().load();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('HUD stage renders filters, telemetry and real globe',
      (tester) async {
    await pumpHome(tester);
    expect(find.byKey(const Key('atlas-globe')), findsOneWidget);
    expect(find.byKey(const Key('telemetry')), findsOneWidget);
    expect(find.text('实体 SIM'), findsWidgets);
    expect(find.text('5ber·eSTK 写卡器'), findsWidgets);
    expect(find.textContaining('177 国'), findsOneWidget);

    await tester.tap(find.byKey(const Key('media-esim')));
    await tester.pump();
    expect(find.byType(FlipSimCard), findsNWidgets(2));
    await tester.tap(find.byKey(const Key('country-JP')));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(FlipSimCard), findsOneWidget);
    expect(find.textContaining(RegExp(r'139\.[67]°E')),
        findsOneWidget); // flew to Tokyo
  });

  testWidgets('15-slot matrix reflects programmable cards and slot taps',
      (tester) async {
    await pumpHome(tester);
    expect(find.text('占用 3 / 15 槽位'), findsOneWidget);
    await tester.tap(find.byKey(const Key('slot-2')));
    await tester.pump();
    expect(find.textContaining('槽位 #2 已占用 · Club SIM (CSL)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('slot-9')));
    await tester.pump();
    expect(find.text('槽位 #9 空闲可用'), findsOneWidget);
    expect(find.byKey(const Key('slot-write')), findsOneWidget);
  });

  testWidgets('card flips to its back face in ~650 ms without mirroring',
      (tester) async {
    await pumpHome(tester);
    const id = 'sim-cn-cmcc';
    expect(find.byKey(const Key('card-front-$id')), findsOneWidget);
    await tester.tap(find.byKey(const Key('flip-$id')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('card-front-$id')), findsNothing);
    expect(find.byKey(const Key('card-back-$id')), findsOneWidget);
    expect(find.text('8986 0012 1928 3746 551'), findsOneWidget);
    final mirror = tester.widget<Transform>(find
        .ancestor(
            of: find.byKey(const Key('card-back-$id')),
            matching: find.byType(Transform))
        .first);
    expect(mirror.transform.storage[0], closeTo(-1, 1e-9)); // pre-rotated π
  });

  testWidgets('wheel zoom is clamped to 1.0x-2.0x and stays inside the stage',
      (tester) async {
    await pumpHome(tester);
    final c = tester.widget<HudStage>(find.byType(HudStage)).controller;
    c.spinning = false;
    final globe = find.byKey(const Key('atlas-globe'));
    final pointer = TestPointer(1, PointerDeviceKind.mouse)
      ..hover(tester.getCenter(globe));
    Future<void> wheel(double dy, int times) async {
      for (var i = 0; i < times; i++) {
        await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
      }
      await tester.pump();
    }

    await wheel(100, 10);
    expect(c.zoom, GlobeController.minZoom);
    expect(c.zoom, 1.0);
    final atMin = await screenPixels(tester);

    await wheel(-100, 20);
    expect(c.zoom, GlobeController.maxZoom);
    expect(c.zoom, 2.0);
    final atMax = await screenPixels(tester);

    final stage = tester.getRect(find.byKey(const Key('globe-stage')));
    expect(tester.getRect(globe), stage);
    // At 2.0x the sphere is far larger than the stage, so only the clip keeps
    // it inside: every pixel outside the stage (HUD strip with the media
    // filter pills, radar drawer, frame) must be identical to 1.0x.
    final radius = stage.shortestSide * 0.42 * c.zoom;
    expect(radius * 2, greaterThan(stage.height));
    expect(stage.overlaps(tester.getRect(find.byKey(const Key('media-all')))),
        isFalse);
    var diff = 0;
    for (var y = 0; y < atMax.height; y++) {
      for (var x = 0; x < atMax.width; x++) {
        if (stage.contains(Offset(x + .5, y + .5))) continue;
        final i = (y * atMax.width + x) * 4;
        for (var k = 0; k < 4; k++) {
          if (atMax.rgba.getUint8(i + k) != atMin.rgba.getUint8(i + k)) {
            diff++;
            break;
          }
        }
      }
    }
    expect(diff, 0, reason: 'globe pixels leaked outside the stage');
  });

  testWidgets('overlapping check-ins both persist', (tester) async {
    await pumpHome(tester, repo: _SlowSaveRepository());
    const ids = ['sim-us-tmobile', 'sim-cn-cmcc'];
    for (final id in ids) {
      await tester.tap(find.byKey(Key('checkin-$id')));
    }
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    final today = dateOnly(DateTime.now());
    final saved = await stored();
    for (final id in ids) {
      expect(saved.firstWhere((c) => c.id == id).lastKeepAliveDate, today);
    }
  });

  testWidgets('check-in, delete and add persist locally', (tester) async {
    await pumpHome(tester);
    const id = 'sim-us-tmobile';
    expect(find.text('P1 · 剩 12 天'), findsOneWidget);
    await tester.tap(find.byKey(const Key('checkin-$id')));
    await tester.pump();
    expect(find.text('P2 · 剩 30 天'), findsWidgets);
    expect((await stored()).firstWhere((c) => c.id == id).daysRemaining(), 30);

    await tester.tap(find.byKey(const Key('flip-$id')));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.byKey(const Key('delete-$id')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('confirm-delete')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('占用 2 / 15 槽位'), findsOneWidget);
    expect((await stored()).length, 4);

    await tester.tap(find.byKey(const Key('slot-5')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('slot-write')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byKey(const Key('field-carrier')), 'Ubigi');
    await tester.tap(find.byKey(const Key('save-card')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('占用 3 / 15 槽位'), findsOneWidget);
    final saved = (await stored()).firstWhere((c) => c.carrierName == 'Ubigi');
    expect(saved.estkSlotNumber, 5);
    expect(saved.mediaType, MediaType.programmable);
  });

  testWidgets('form blocks saving a negative cycle cost', (tester) async {
    await pumpHome(tester);
    final before = (await stored()).length;
    await tester.tap(find.byKey(const Key('add-card')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byKey(const Key('field-carrier')), 'Neg');
    await tester.enterText(find.byKey(const Key('field-cost')), '-5');
    await tester.tap(find.byKey(const Key('save-card')));
    await tester.pump();
    expect(find.textContaining('周期费用不能为负数'), findsOneWidget);
    expect(find.byKey(const Key('save-card')), findsOneWidget);
    expect((await stored()).length, before);

    await tester.enterText(find.byKey(const Key('field-cost')), '5');
    await tester.tap(find.byKey(const Key('save-card')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect((await stored()).firstWhere((c) => c.carrierName == 'Neg').cycleCost,
        5);
  });

  test('load quarantines stored cards with negative fees', () async {
    final good = {
      'id': 'ok',
      'carrierName': 'OK',
      'nextDeadlineDate': '2027-01-01'
    };
    final bad = {
      'id': 'bad',
      'carrierName': 'Bad',
      'cycleCost': -8,
      'nextDeadlineDate': '2027-01-01'
    };
    SharedPreferences.setMockInitialValues({
      SimRepository.storageKey: jsonEncode([good, bad]),
      SimRepository.seededKey: true,
    });
    final repo = SimRepository();
    final cards = await repo.load();
    expect(cards.map((c) => c.id), ['ok']);
    expect(repo.lastLoadErrors.single, contains('第 2 张卡片'));
    expect(repo.lastLoadErrors.single, contains('不能为负数'));
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString(SimRepository.rejectedKey)!), [bad]);
    expect((await SimRepository().load()).map((c) => c.id), ['ok']);
  });

  test('failed quarantine leaves the stored vault untouched', () async {
    final stored = jsonEncode([
      {'id': 'ok', 'nextDeadlineDate': '2027-01-01'},
      {'id': 'bad', 'cycleCost': -8, 'nextDeadlineDate': '2027-01-01'},
    ]);
    SharedPreferences.setMockInitialValues({
      SimRepository.storageKey: stored,
      SimRepository.rejectedKey: 'not json',
      SimRepository.seededKey: true,
    });
    final repo = SimRepository();
    final cards = await repo.load();
    expect(cards.map((c) => c.id), ['ok']);
    expect(repo.lastLoadErrors, hasLength(1));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SimRepository.storageKey), stored);
    await expectLater(repo.save(cards), throwsFormatException);
    expect(prefs.getString(SimRepository.storageKey), stored);
    expect(prefs.getString(SimRepository.rejectedKey), 'not json');
  });

  testWidgets('failed save keeps UI and vault unchanged, no false success',
      (tester) async {
    final stored = jsonEncode([
      {'id': 'ok', 'nextDeadlineDate': '2027-01-01'},
      {'id': 'bad', 'cycleCost': -8, 'nextDeadlineDate': '2027-01-01'},
    ]);
    SharedPreferences.setMockInitialValues({
      SimRepository.storageKey: stored,
      SimRepository.rejectedKey: 'not json',
      SimRepository.seededKey: true,
    });
    await pumpHome(tester);
    await tester.pump(const Duration(seconds: 5));
    final before = find.textContaining('剩').evaluate().length;
    expect(find.byKey(const Key('checkin-ok')), findsOneWidget);
    await tester.tap(find.byKey(const Key('checkin-ok')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(find.textContaining('保号打卡成功'), findsNothing);
    expect(find.textContaining('剩').evaluate().length, before);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SimRepository.storageKey), stored);
  });

  testWidgets('home page reports quarantined cards', (tester) async {
    SharedPreferences.setMockInitialValues({
      SimRepository.storageKey: jsonEncode([
        {'id': 'bad', 'monthlyFee': -1, 'nextDeadlineDate': '2027-01-01'}
      ]),
      SimRepository.seededKey: true,
    });
    await pumpHome(tester);
    expect(find.textContaining('已拦截 1 张非法卡片'), findsOneWidget);
  });
}

class _SlowSaveRepository extends SimRepository {
  @override
  Future<void> save(List<SimCard> cards) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await super.save(cards);
  }
}
