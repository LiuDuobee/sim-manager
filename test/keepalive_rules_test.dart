import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sim_manager/features/globe/topojson.dart';
import 'package:sim_manager/main.dart';
import 'package:sim_manager/pages/home_page.dart';
import 'package:sim_manager/services/carrier_presets.dart';
import 'package:sim_manager/services/seed_cards.dart';
import 'package:sim_manager/services/sim_repository.dart';

/// Phase 1: keep-alive types + renewal rules, carrier presets, renewal
/// passport with undo, archive instead of delete, yearly cost overview.
void main() {
  final now = DateTime(2026, 11, 21);
  final today = dateOnly(now);

  SimCard card({
    KeepAliveType type = KeepAliveType.activity,
    RenewalBasis basis = RenewalBasis.fromAction,
    int deadlineIn = 10,
    int cycle = 30,
    double cost = 3,
    String currency = 'USD',
    BillingCycle billing = BillingCycle.monthly,
  }) =>
      SimCard(
        id: 'x',
        carrierName: 'X',
        phoneNumber: '',
        countryCode: 'US',
        mediaType: MediaType.physical,
        nextDeadlineDate: addDays(today, deadlineIn),
        keepAliveType: type,
        renewalBasis: basis,
        keepAliveCycleDays: cycle,
        cycleCost: cost,
        currency: currency,
        billingCycle: billing,
      );

  group('renewal rules', () {
    test('按操作当天重算 restarts the cycle from today', () {
      final c = card().checkIn(now: now);
      expect(c.nextDeadlineDate, addDays(today, 30));
    });

    test('按原到期日顺延 extends the current deadline', () {
      final c = card(basis: RenewalBasis.fromDeadline).checkIn(now: now);
      expect(c.nextDeadlineDate, addDays(today, 40));
    });

    test('a lapsed deadline restarts from today even when 顺延', () {
      final c = card(basis: RenewalBasis.fromDeadline, deadlineIn: -5)
          .checkIn(now: now);
      expect(c.nextDeadlineDate, addDays(today, 30));
    });

    test('validity cards log a top-up, activity cards a check-in', () {
      final v = card(type: KeepAliveType.validity).checkIn(now: now);
      expect(v.events.single.type, CardEventType.topUp);
      expect(v.events.single.amount, 3);
      expect(v.events.single.currency, 'USD');
      expect(v.events.single.deadline, v.nextDeadlineDate);
      final a = card().checkIn(now: now);
      expect(a.events.single.type, CardEventType.checkIn);
      expect(a.events.single.amount, isNull);
      expect(a.keepAliveLog, [today]);
    });

    test('radar verb follows the keep-alive type', () {
      expect(KeepAliveType.activity.verb, '需活跃');
      expect(KeepAliveType.validity.verb, '需充值');
    });
  });

  group('yearly cost', () {
    test('monthly ×12, yearly ×1, PayGo once per keep-alive cycle', () {
      expect(card().annualCost, 36);
      expect(card(billing: BillingCycle.yearly, cost: 6).annualCost, 6);
      expect(
          card(billing: BillingCycle.payGo, cost: 0.3, cycle: 180).annualCost,
          closeTo(0.3 * 365 / 180, 1e-9));
    });

    test('grouped by currency, zero-cost cards skipped', () {
      final byCurrency = annualCostByCurrency(buildSeedCards(now));
      expect(byCurrency, {'CNY': 96, 'HKD': 6, 'JPY': 12936, 'USD': 36});
    });
  });

  group('carrier presets', () {
    test('every preset is a usable rule set', () {
      final ids = <String>{};
      for (final p in carrierPresets) {
        expect(ids.add(p.id), isTrue, reason: 'duplicate ${p.id}');
        expect(p.cycleDays, greaterThan(0));
        expect(feeError(p.cycleCost, 'cost'), isNull);
        expect(p.rechargeUrl, startsWith('https://'));
        expect(exchangeRatesToCny, contains(p.currency));
        expect(p.annualCost, greaterThan(0));
      }
      for (final id in [
        'giffgaff',
        'club-sim',
        'povo2',
        'tmobile-paygo',
        'vodafone-uk',
        'ais'
      ]) {
        expect(presetById(id), isNotNull, reason: id);
      }
    });

    test('applyTo copies rules and keeps identity and history', () {
      final base = card().checkIn(now: now);
      final c = presetById('club-sim')!.applyTo(base);
      expect(c.id, base.id);
      expect(c.events, base.events);
      expect(c.keepAliveType, KeepAliveType.validity);
      expect(c.renewalBasis, RenewalBasis.fromDeadline);
      expect(c.keepAliveCycleDays, 365);
      expect(c.currency, 'HKD');
      expect(c.carrierPresetId, 'club-sim');
      expect(c.rechargeUrl, isNotEmpty);
    });
  });

  group('JSON compatibility', () {
    test('old records get defaults and their check-in log as passport', () {
      final c = SimCard.fromJson({
        'id': 'old',
        'carrierName': 'Old',
        'nextDeadlineDate': '2027-01-01',
        'keepAliveLog': ['2026-10-01', '2026-04-01'],
      });
      expect(c.keepAliveType, KeepAliveType.activity);
      expect(c.renewalBasis, RenewalBasis.fromAction);
      expect(c.carrierPresetId, '');
      expect(c.archivedAt, isNull);
      expect(c.events.map((e) => e.type), everyElement(CardEventType.checkIn));
      expect(c.events.map((e) => e.at),
          [DateTime(2026, 10, 1), DateTime(2026, 4, 1)]);
    });

    test('new fields, passport and archive date round-trip', () {
      final c = presetById('giffgaff')!
          .applyTo(card())
          .checkIn(now: now)
          .withEvent(
              CardEvent(at: today, type: CardEventType.edit, note: '修改 号码'))
          .copyWith(archivedAt: () => today);
      final back = SimCard.decodeList(SimCard.encodeList([c])).single;
      expect(back.toJson(), c.toJson());
      expect(back.events, c.events);
    });

    test('a negative passport amount is rejected, not zeroed', () {
      final raw = card().toJson()
        ..['events'] = [
          {'at': '2026-11-01', 'type': 'TopUp', 'amount': -5}
        ];
      expect(
          () => SimCard.decodeList(jsonEncode([raw])),
          throwsA(isA<FormatException>()
              .having((e) => e.message, 'message', contains('不能为负数'))));
    });

    test('invalid archived records go to the quarantine on load', () async {
      final good = card().copyWith(id: 'ok', archivedAt: () => today);
      final bad = card().toJson()
        ..['id'] = 'bad'
        ..['events'] = [
          {'at': '2026-11-01', 'type': 'TopUp', 'amount': -5}
        ];
      SharedPreferences.setMockInitialValues({
        SimRepository.storageKey: SimCard.encodeList([]),
        SimRepository.archiveKey: jsonEncode([good.toJson(), bad]),
      });
      final repo = SimRepository();
      await repo.load();
      final archive = await repo.loadArchive();
      expect(archive.map((c) => c.id), ['ok']);
      expect(repo.lastLoadErrors.single, contains('不能为负数'));
      await repo.saveArchive(archive);
      final prefs = await SharedPreferences.getInstance();
      final rejected =
          jsonDecode(prefs.getString(SimRepository.rejectedKey)!) as List;
      expect(rejected.single['id'], 'bad');
    });
  });

  group('home page', () {
    final atlas = decodeWorldAtlas(
        File('assets/geo/countries-110m.json').readAsStringSync());

    Future<void> pumpHome(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          SimVaultApp(home: HomePage(atlasLoader: () async => atlas)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<void> frames(WidgetTester tester, [int n = 4]) async {
      for (var i = 0; i < n; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<List<SimCard>> vault() async => SimRepository().load();
    Future<List<SimCard>> archive() async {
      final r = SimRepository();
      await r.load();
      return r.loadArchive();
    }

    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('check-in can be undone within the 5 s snackbar',
        (tester) async {
      await pumpHome(tester);
      const id = 'sim-us-tmobile';
      final before = (await vault()).firstWhere((c) => c.id == id);
      await tester.tap(find.byKey(const Key('checkin-$id')));
      await tester.pump();
      final checked = (await vault()).firstWhere((c) => c.id == id);
      expect(checked.events.first.type, CardEventType.topUp);
      expect(find.byKey(const Key('undo-checkin')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.byKey(const Key('undo-checkin')));
      await tester.pump();
      await tester.pump();
      final undone = (await vault()).firstWhere((c) => c.id == id);
      expect(undone.toJson(), before.toJson());
      expect(find.text('P1 · 剩 12 天'), findsOneWidget);
    });

    testWidgets('undo is gone after 5 s', (tester) async {
      await pumpHome(tester);
      await tester.tap(find.byKey(const Key('checkin-sim-cn-cmcc')));
      await tester.pump();
      expect(find.byKey(const Key('undo-checkin')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('undo-checkin')), findsNothing);
    });

    testWidgets('archive keeps history, restores, and purges', (tester) async {
      await pumpHome(tester);
      const id = 'sim-hk-clubsim';
      await tester.tap(find.byKey(const Key('checkin-$id')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('flip-$id')));
      await frames(tester, 7);
      await tester.tap(find.byKey(const Key('delete-$id')));
      await frames(tester, 3);
      await tester.tap(find.byKey(const Key('confirm-delete')));
      await frames(tester, 3);

      expect((await vault()).map((c) => c.id), isNot(contains(id)));
      final archived = (await archive()).single;
      expect(archived.id, id);
      expect(archived.archivedAt, dateOnly(DateTime.now()));
      expect(archived.events.map((e) => e.type),
          [CardEventType.archive, CardEventType.topUp]);
      expect(find.byKey(const Key('flip-card-$id')), findsNothing);
      expect(find.text('占用 2 / 15 槽位'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('archive-toggle')));
      await tester.tap(find.byKey(const Key('archive-toggle')));
      await tester.pump();
      expect(find.byKey(const Key('archived-$id')), findsOneWidget);
      await tester.tap(find.byKey(const Key('restore-$id')));
      await frames(tester, 2);
      final restored = (await vault()).firstWhere((c) => c.id == id);
      expect(restored.archivedAt, isNull);
      expect(restored.events.first.type, CardEventType.restore);
      expect(restored.estkSlotNumber, 2);
      expect(await archive(), isEmpty);
      expect(find.text('占用 3 / 15 槽位'), findsOneWidget);

      // Archive again, then delete for good.
      await tester.ensureVisible(find.byKey(const Key('flip-$id')));
      await tester.tap(find.byKey(const Key('flip-$id')));
      await frames(tester, 7);
      await tester.tap(find.byKey(const Key('delete-$id')));
      await frames(tester, 3);
      await tester.tap(find.byKey(const Key('confirm-delete')));
      await frames(tester, 3);
      await tester.ensureVisible(find.byKey(const Key('archive-toggle')));
      if (find.byKey(const Key('purge-$id')).evaluate().isEmpty) {
        await tester.tap(find.byKey(const Key('archive-toggle')));
        await tester.pump();
      }
      await tester.tap(find.byKey(const Key('purge-$id')));
      await frames(tester, 3);
      await tester.tap(find.byKey(const Key('confirm-purge')));
      await frames(tester, 3);
      expect(await archive(), isEmpty);
      expect((await vault()).map((c) => c.id), isNot(contains(id)));
      expect(find.byKey(const Key('archive-toggle')), findsNothing);
    });

    testWidgets('bento shows the yearly cost per currency', (tester) async {
      await pumpHome(tester);
      expect(tester.widget<Text>(find.byKey(const Key('annual-cost'))).data,
          'CNY 96 · HKD 6 · JPY 12936 · USD 36');
    });

    testWidgets('passport dialog lists rules, yearly cost and events',
        (tester) async {
      await pumpHome(tester);
      const id = 'sim-us-tmobile';
      await tester.tap(find.byKey(const Key('checkin-$id')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('flip-$id')));
      await frames(tester, 7);
      await tester.tap(find.byKey(const Key('passport-$id')));
      await frames(tester, 3);
      expect(find.byKey(const Key('passport-dialog')), findsOneWidget);
      expect(find.textContaining('有效期型 · 按操作当天重算'), findsWidgets);
      expect(find.textContaining('预估年成本 USD 36'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('passport-dialog')),
              matching: find.textContaining('充值续期 USD 3')),
          findsOneWidget);
    });

    testWidgets('choosing a preset fills rules and is saved with the card',
        (tester) async {
      await pumpHome(tester);
      await tester.tap(find.byKey(const Key('add-card')));
      await frames(tester, 5);
      await tester.tap(find.byKey(const Key('field-preset')));
      await frames(tester, 3);
      await tester.tap(find.textContaining('giffgaff UK · 180 天').last);
      await frames(tester, 3);
      expect(find.textContaining('预估年成本 GBP 0.61'), findsOneWidget);
      await tester.tap(find.byKey(const Key('save-card')));
      await frames(tester, 5);
      final saved = (await vault()).firstWhere(
          (c) => c.carrierPresetId == 'giffgaff' && c.id != 'sim-gb-giffgaff');
      expect(saved.carrierName, 'giffgaff UK');
      expect(saved.countryCode, 'GB');
      expect(saved.keepAliveCycleDays, 180);
      expect(saved.rechargeUrl, 'https://www.giffgaff.com/top-up');
      expect(saved.events.single.type, CardEventType.create);
    });

    testWidgets('editing a card records which fields changed', (tester) async {
      await pumpHome(tester);
      const id = 'sim-cn-cmcc';
      await tester.tap(find.byKey(const Key('flip-$id')));
      await frames(tester, 7);
      await tester.tap(find.byKey(const Key('edit-$id')));
      await frames(tester, 5);
      await tester.enterText(find.byKey(const Key('field-phone')), '+86 1');
      await tester.tap(find.byKey(const Key('save-card')));
      await frames(tester, 5);
      final e = (await vault()).firstWhere((c) => c.id == id).events.first;
      expect(e.type, CardEventType.edit);
      expect(e.note, '修改 号码');
    });

    testWidgets('backup export carries the archive, import splits it',
        (tester) async {
      final archived = buildSeedCards(DateTime.now())
          .first
          .copyWith(id: 'arch', archivedAt: () => dateOnly(DateTime.now()));
      final active = buildSeedCards(DateTime.now())[1];
      SharedPreferences.setMockInitialValues({
        SimRepository.storageKey: SimCard.encodeList([active]),
        SimRepository.archiveKey: SimCard.encodeList([archived]),
        SimRepository.seededKey: true,
      });
      await pumpHome(tester);
      await tester.tap(find.byKey(const Key('open-backup')));
      await frames(tester, 5);
      final exported = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((t) => t.data ?? '')
          .join();
      expect(exported, contains('"archivedAt"'));
      expect(SimCard.decodeList(exported).map((c) => c.id),
          containsAll(['arch', active.id]));

      await tester.enterText(find.byKey(const Key('import-field')), exported);
      await tester.tap(find.byKey(const Key('do-import')));
      await frames(tester, 3);
      await tester.tap(find.byKey(const Key('confirm-import')));
      await frames(tester, 5);
      expect((await vault()).map((c) => c.id), [active.id]);
      expect((await archive()).map((c) => c.id), ['arch']);
    });
  });
}
