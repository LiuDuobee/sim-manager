import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sim_manager/features/globe/topojson.dart';
import 'package:sim_manager/features/hud/hud_theme.dart';
import 'package:sim_manager/main.dart';
import 'package:sim_manager/models/medium.dart';
import 'package:sim_manager/pages/home_page.dart';
import 'package:sim_manager/pages/sim_form_page.dart';
import 'package:sim_manager/services/estk_slots.dart';
import 'package:sim_manager/services/seed_cards.dart';
import 'package:sim_manager/services/sim_repository.dart';

/// v3.4.0 PR-B: media (载体) registry, multi-medium matrix, frosted glass.
void main() {
  final now = DateTime(2026, 11, 21);
  final atlas = decodeWorldAtlas(
      File('assets/geo/countries-110m.json').readAsStringSync());

  SimCard card(String id,
          {MediaType media = MediaType.programmable,
          int? slot,
          String? mediumId}) =>
      SimCard(
        id: id,
        carrierName: id,
        phoneNumber: '',
        countryCode: 'GB',
        mediaType: media,
        nextDeadlineDate: addDays(dateOnly(now), 30),
        estkSlotNumber: slot,
        mediumId: mediumId,
      );

  const v3 = Medium(
      id: 'm-v3',
      name: '9eSIM V3',
      kind: MediumKind.euicc,
      capacity: 50,
      modelId: '9esim-v3');
  const phone = Medium(
      id: 'm-phone',
      name: '手机内置 eSIM',
      kind: MediumKind.builtinEsim,
      capacity: 10,
      modelId: 'builtin');

  group('medium presets', () {
    test('brand / model capacities match the brief', () {
      int? cap(String id) => mediumModelById(id)!.capacity;
      expect([cap('estk-c'), cap('estk-plus'), cap('estk-max')], [13, 26, 60]);
      expect(mediumModelById('estk-max')!.capacityLabel, '≈60');
      expect(
          [cap('9esim-v0'), cap('9esim-v0max'), cap('9esim-v3')], [15, 30, 50]);
      expect(
          [cap('xesim-x1'), cap('xesim-x2'), cap('xesim-x2pro')], [15, 30, 30]);
      expect(mediumModelById('beesim-v1')!.capacityLabel, '约 8–9');
      expect([cap('switch-pro'), cap('switch-max'), cap('switch-ultra')],
          [15, 15, 50]);
      for (final id in [
        'roamhop-lite',
        'roamhop-plus',
        'roamhop-max',
        'esim-me',
        'esimkit',
        'blank'
      ]) {
        expect(cap(id), isNull, reason: id);
        expect(mediumModelById(id)!.capacityLabel, '容量自填');
      }
      expect(cap('builtin'), builtinEsimDefaultCapacity);
      expect(builtinEsimDefaultCapacity, 10);
    });

    test('5ber is listed for existing cards only, flagged not recommended', () {
      final m = mediumModelById('5ber')!;
      expect(m.capacity, 15);
      expect(m.notRecommended, isTrue);
      expect(m.note, contains('停'));
      expect(m.note, contains('不推荐新购'));
      expect(mediumModels.where((x) => x.notRecommended).map((x) => x.id),
          ['5ber']);
    });

    test('medium kinds use the three medium labels', () {
      expect(MediaType.physical.mediumLabel, '运营商实体卡');
      expect(MediaType.esim.mediumLabel, '设备内置 eSIM');
      expect(MediaType.programmable.mediumLabel, '可复写 eUICC 卡');
      // HUD pills keep the v3.2 wording.
      expect(MediaType.programmable.label, '5ber·eSTK 写卡器');
    });
  });

  group('migration and layout', () {
    test('old cards land on the legacy 15-slot eSTK with the same slots', () {
      final seeds = buildSeedCards(now);
      final legacy = layoutEstkSlots(seeds);
      final generic = layoutMediumSlots(legacyEstkMedium, seeds);
      expect(generic.slots.map((k, v) => MapEntry(k, v.id)),
          legacy.slots.map((k, v) => MapEntry(k, v.id)));
      expect(generic.usageLabel, '占用 3 / 15 槽位');
      expect(
          seeds
              .where((c) => c.onProgrammableMedium)
              .map((c) => c.resolvedMediumId),
          everyElement(legacyMediumId));
    });

    test('missing / broken media storage falls back to the legacy eSTK',
        () async {
      SharedPreferences.setMockInitialValues({});
      expect((await SimRepository().loadMedia()).single.id, legacyMediumId);
      SharedPreferences.setMockInitialValues(
          {'flutter.${SimRepository.mediaKey}': '{oops'});
      SharedPreferences.setMockInitialValues({SimRepository.mediaKey: '{oops'});
      expect((await SimRepository().loadMedia()).single.id, legacyMediumId);
      SharedPreferences.setMockInitialValues({});
      final repo = SimRepository();
      await repo.saveMedia([legacyEstkMedium, v3]);
      expect((await repo.loadMedia()).map((m) => m.id), ['estk', 'm-v3']);
    });

    test('invalid medium entries are skipped, not zeroed', () {
      final media = Medium.decodeList([
        v3.toJson(),
        {'id': 'bad', 'capacity': 0},
        {'id': 'm-v3', 'capacity': 9},
        'junk',
      ]);
      expect(media.single.capacity, 50);
    });

    test('mediumId round-trips; old JSON has none', () {
      final c = card('a', slot: 7, mediumId: 'm-v3');
      final back = SimCard.fromJson(
          jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>);
      expect(back.mediumId, 'm-v3');
      final old =
          SimCard.fromJson(card('b', slot: 2).toJson()..remove('mediumId'));
      expect(old.mediumId, isNull);
      expect(old.resolvedMediumId, legacyMediumId);
    });

    test('each medium lays out its own capacity and cards', () {
      final cards = [
        card('e1', slot: 1),
        card('v1', slot: 42, mediumId: 'm-v3'),
        card('v2', mediumId: 'm-v3'),
        card('p1', media: MediaType.esim, mediumId: 'm-phone', slot: 3),
        card('phys', media: MediaType.physical),
      ];
      final l = layoutMediumSlots(v3, cards);
      expect(l.capacity, 50);
      expect(l.rows, 10);
      expect(l.slots[42]!.id, 'v1');
      expect(l.slots[1]!.id, 'v2');
      expect(l.usageLabel, '占用 2 / 50 槽位');
      expect(layoutMediumSlots(phone, cards).slots.keys, [3]);
      expect(layoutEstkSlots(cards).slots.values.map((c) => c.id), ['e1']);
    });

    test('cards pointing at an unknown medium get a placeholder', () {
      final media = reconcileMedia([v3], [card('x', mediumId: 'gone')]);
      expect(media.map((m) => m.id), ['m-v3', 'gone']);
      expect(media.last.name, '未知载体');
    });
  });

  group('glass', () {
    double ratio(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return (math.max(x, y) + .05) / (math.min(x, y) + .05);
    }

    test('floating tint keeps body text ≥ 4.5:1 over black or white content',
        () {
      for (final p in [HudPalette.dark, HudPalette.light]) {
        for (final under in [Colors.black, Colors.white, p.bg]) {
          final face = Color.alphaBlend(p.floatTint, under);
          expect(ratio(p.fg, face), greaterThanOrEqualTo(4.5),
              reason: '${p.brightness} fg over $under');
          expect(ratio(p.sky, face), greaterThanOrEqualTo(3),
              reason: '${p.brightness} accent over $under');
        }
      }
    });

    test('saturation matrix keeps grey and boosts colour', () {
      final m = saturationMatrix(1.8);
      double row(int r, List<double> rgb) =>
          m[r * 5] * rgb[0] + m[r * 5 + 1] * rgb[1] + m[r * 5 + 2] * rgb[2];
      expect(row(0, [.5, .5, .5]), closeTo(.5, 1e-9));
      expect(row(0, [.8, .2, .2]), greaterThan(.8));
    });
  });

  group('home page', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<void> frames(WidgetTester tester, [int n = 4]) async {
      for (var i = 0; i < n; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> pumpApp(WidgetTester tester, {bool phone = false}) async {
      tester.view.physicalSize =
          phone ? const Size(1080, 2400) : const Size(1600, 3000);
      tester.view.devicePixelRatio = phone ? 2.625 : 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          SimVaultApp(home: HomePage(atlasLoader: () async => atlas)));
      await tester.pump();
      await frames(tester, 2);
    }

    testWidgets('top bar and dock are frosted, grouped floating glass',
        (tester) async {
      await pumpApp(tester, phone: true);
      final bar = find.byKey(const Key('top-bar'));
      final dock = find.byKey(const Key('mobile-dock'));
      for (final f in [bar, dock]) {
        final filter = tester.widget<BackdropFilter>(
            find.descendant(of: f, matching: find.byType(BackdropFilter)));
        expect(filter.filter.toString(), contains('blur'));
        expect(filter.filter.toString(), contains('matrix'));
      }
      expect(find.byType(BackdropGroup), findsOneWidget);
      // Content scrolls under the bar: the scroll view starts at the bar's
      // bottom edge and paints past it.
      final scroll = find.byKey(const Key('mobile-scroll'));
      expect(tester.getTopLeft(scroll).dy,
          closeTo(tester.getBottomLeft(bar).dy, 1));
      expect(
          tester.widget<SingleChildScrollView>(scroll).clipBehavior, Clip.none);
    });

    testWidgets('desktop list scrolls under the floating top bar',
        (tester) async {
      await pumpApp(tester);
      tester.view.physicalSize = const Size(1600, 1000);
      await frames(tester);
      final bar = find.byKey(const Key('top-bar'));
      expect(bar, findsOneWidget);
      final list = tester.widget<ListView>(find.byType(ListView).first);
      expect(list.clipBehavior, Clip.none);
      // Dragging the bar scrolls the page.
      await tester.drag(find.text('SIMVault').first, const Offset(0, -300));
      await frames(tester);
      final pos = tester
          .state<ScrollableState>(find
              .descendant(
                  of: find.byType(ListView).first,
                  matching: find.byType(Scrollable))
              .first)
          .position;
      expect(pos.pixels, greaterThan(100));
    });

    testWidgets('matrix switches media; big media scroll; nickname kept',
        (tester) async {
      final seeds = buildSeedCards(now);
      await SimRepository().save([
        ...seeds,
        card('v3a', slot: 37, mediumId: 'm-v3'),
      ]);
      await SimRepository().saveMedia([legacyEstkMedium, v3]);
      await pumpApp(tester);
      expect(find.text('占用 3 / 15 槽位'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('medium-tab-m-v3')));
      await tester.tap(find.byKey(const Key('medium-tab-m-v3')));
      await frames(tester);
      expect(find.text('占用 1 / 50 槽位'), findsOneWidget);
      expect(find.byKey(const Key('medium-grid-scroll')), findsOneWidget);
      expect(find.byKey(const Key('slot-50'), skipOffstage: false),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('medium-tab-estk')));
      await frames(tester);
      expect(find.text('占用 3 / 15 槽位'), findsOneWidget);
      expect(find.byKey(const Key('slot-16')), findsNothing);
    });

    testWidgets('media page adds a preset medium; occupied ones stay',
        (tester) async {
      await pumpApp(tester);
      await tester.ensureVisible(find.byKey(const Key('manage-media')));
      await tester.tap(find.byKey(const Key('manage-media')));
      await frames(tester, 6);
      // The legacy eSTK holds cards: removing it is refused.
      await tester.tap(find.byKey(const Key('medium-remove-estk')));
      await frames(tester);
      expect(find.byKey(const Key('medium-row-estk')), findsOneWidget);

      await tester.tap(find.byKey(const Key('media-add')));
      await frames(tester, 6);
      await tester.tap(find.byKey(const Key('medium-model')));
      await frames(tester);
      await tester.tap(find.textContaining('5ber · 15').last);
      await frames(tester);
      expect(find.byKey(const Key('medium-model-note')), findsOneWidget);
      await tester.tap(find.byKey(const Key('medium-model')));
      await frames(tester);
      await tester.tap(find.textContaining('9eSIM V3 · 50').last);
      await frames(tester);
      expect(
          tester
              .widget<TextFormField>(find.byKey(const Key('medium-capacity')))
              .controller!
              .text,
          '50');
      await tester.tap(find.byKey(const Key('medium-ok')));
      await frames(tester, 6);
      await tester.tap(find.byKey(const Key('media-save')));
      await frames(tester, 8);
      final media = await SimRepository().loadMedia();
      expect(media.map((m) => m.name), ['eSTK', '9eSIM V3']);
      expect(media.last.capacity, 50);
      expect(find.byKey(Key('medium-tab-${media.last.id}')), findsOneWidget);
    });

    testWidgets('backup carries media; an old backup keeps current media',
        (tester) async {
      await SimRepository().saveMedia([legacyEstkMedium, v3]);
      await pumpApp(tester);
      await tester.tap(find.byKey(const Key('open-backup')));
      await frames(tester, 8);
      final exported = tester
          .widget<SelectableText>(find.byKey(const Key('backup-json')))
          .data!;
      final decoded = jsonDecode(exported) as Map<String, dynamic>;
      expect((decoded['media'] as List).map((m) => m['id']), ['estk', 'm-v3']);
      expect(SimCard.decodeList(exported), hasLength(5));

      final old = SimCard.encodeList([card('legacy', slot: 4)]);
      await tester.enterText(find.byKey(const Key('import-field')), old);
      await tester.tap(find.byKey(const Key('do-import')));
      await frames(tester);
      await tester.tap(find.byKey(const Key('confirm-import')));
      await frames(tester, 8);
      expect((await SimRepository().loadMedia()).map((m) => m.id),
          ['estk', 'm-v3']);
    });
  });

  group('form', () {
    Future<SimCard? Function()> openForm(WidgetTester tester,
        {SimCard? initial,
        int? presetSlot,
        String? presetMediumId,
        List<SimCard> existing = const []}) async {
      tester.view.physicalSize = const Size(1600, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SimCard? result;
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => TextButton(
                  onPressed: () async => result = await Navigator.push(
                      context,
                      MaterialPageRoute<SimCard>(
                          builder: (_) => SimFormPage(
                              initial: initial,
                              presetSlot: presetSlot,
                              presetMediumId: presetMediumId,
                              existing: existing,
                              media: const [legacyEstkMedium, v3, phone]))),
                  child: const Text('open')))));
      await tester.tap(find.text('open'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      return () => result;
    }

    Future<void> frames(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('slot from a big medium: capacity and clash per medium',
        (tester) async {
      final result = await openForm(tester,
          presetSlot: 40,
          presetMediumId: 'm-v3',
          existing: [
            card('taken', slot: 41, mediumId: 'm-v3'),
            card('e', slot: 40)
          ]);
      expect(find.text('9eSIM V3 槽位号 (1-50)'), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('field-carrier')), 'giffgaff');
      await tester.enterText(find.byKey(const Key('field-estk-slot')), '41');
      await tester.tap(find.byKey(const Key('save-card')));
      await frames(tester);
      expect(find.text('槽位 #41 已被 taken 占用'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('field-estk-slot')), '51');
      await tester.tap(find.byKey(const Key('save-card')));
      await frames(tester);
      expect(find.text('槽位号需为 1-50'), findsOneWidget);
      // Slot 40 is taken on the eSTK, not on this medium.
      await tester.enterText(find.byKey(const Key('field-estk-slot')), '40');
      await tester.tap(find.byKey(const Key('save-card')));
      await frames(tester);
      expect(result()!.mediumId, 'm-v3');
      expect(result()!.estkSlotNumber, 40);
    });

    testWidgets('picking the built-in eSIM medium sets the eSIM medium type',
        (tester) async {
      final result = await openForm(tester);
      await tester.enterText(find.byKey(const Key('field-carrier')), 'povo');
      await tester.ensureVisible(find.byKey(const Key('field-medium')));
      await tester.tap(find.byKey(const Key('field-medium')));
      await frames(tester);
      await tester.tap(find.text('手机内置 eSIM · 10 槽').last);
      await frames(tester);
      await tester.enterText(find.byKey(const Key('field-estk-slot')), '2');
      await tester.tap(find.byKey(const Key('save-card')));
      await frames(tester);
      expect(result()!.mediaType, MediaType.esim);
      expect(result()!.mediumId, 'm-phone');
      expect(result()!.estkSlotNumber, 2);
    });

    testWidgets('legacy programmable card keeps mediumId null on save',
        (tester) async {
      final legacy =
          buildSeedCards(now).firstWhere((c) => c.onProgrammableMedium);
      final result = await openForm(tester, initial: legacy);
      expect(find.text('eSTK 槽位号 (1-15)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('save-card')));
      await frames(tester);
      expect(result()!.mediumId, isNull);
      expect(result()!.estkSlotNumber, legacy.estkSlotNumber);
    });
  });
}
