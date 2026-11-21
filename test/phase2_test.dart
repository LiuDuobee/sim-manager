import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sim_manager/features/cards/iccid_scanner.dart';
import 'package:sim_manager/features/cards/show_number_page.dart';
import 'package:sim_manager/features/cards/sms_renewal_page.dart';
import 'package:sim_manager/features/globe/topojson.dart';
import 'package:sim_manager/main.dart';
import 'package:sim_manager/pages/home_page.dart';
import 'package:sim_manager/pages/sim_form_page.dart';
import 'package:sim_manager/services/iccid.dart';
import 'package:sim_manager/services/ics_export.dart';
import 'package:sim_manager/services/seed_cards.dart';
import 'package:sim_manager/services/sim_repository.dart';
import 'package:sim_manager/services/sms_parser.dart';
import 'package:sim_manager/services/time_river.dart';

/// Phase 2: time river, ICCID scan, SMS renewal, show number, reminder
/// offsets, tags, privacy mask, eSTK profile nicknames.
void main() {
  final atlas = decodeWorldAtlas(
      File('assets/geo/countries-110m.json').readAsStringSync());
  final now = DateTime.now();

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

  Future<List<SimCard>> vault() async => SimRepository().load();
  SimCard card(List<SimCard> cards, String id) =>
      cards.firstWhere((c) => c.id == id);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  String withCheckDigit(String body) {
    for (var d = 0; d < 10; d++) {
      if (luhnValid('$body$d')) return '$body$d';
    }
    throw StateError('unreachable');
  }

  group('data compatibility', () {
    test('phase-1 JSON without new fields gets defaults', () {
      final json = buildSeedCards(now).first.toJson()
        ..remove('tags')
        ..remove('reminderOffsets')
        ..remove('profileName');
      final c = SimCard.fromJson(json);
      expect(c.tags, isEmpty);
      expect(c.reminderOffsets, SimCard.defaultReminderOffsets);
      expect(c.profileName, '');
    });

    test('new fields round-trip through JSON', () {
      final c = buildSeedCards(now).first.copyWith(
          tags: ['主力', '收藏'], reminderOffsets: [0, 30, 7], profileName: '工作号');
      final back = SimCard.fromJson(
          jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>);
      expect(back.tags, ['主力', '收藏']);
      expect(back.reminderOffsets, [30, 7, 0]);
      expect(back.profileName, '工作号');
    });

    test('invalid offsets / tags are rejected and quarantined', () {
      final good = buildSeedCards(now).first.toJson();
      expect(
          () => SimCard.fromJson({
                ...good,
                'reminderOffsets': [-1]
              }),
          throwsFormatException);
      expect(
          () => SimCard.fromJson({
                ...good,
                'reminderOffsets': [1.5]
              }),
          throwsFormatException);
      expect(() => SimCard.fromJson({...good, 'tags': '主力'}),
          throwsFormatException);
      final partial = SimCard.decodeListPartial(jsonEncode([
        good,
        {
          ...good,
          'id': 'bad',
          'reminderOffsets': [400]
        }
      ]));
      expect(partial.cards, hasLength(1));
      expect(partial.rejected, hasLength(1));
    });
  });

  group('time river', () {
    test('lists deadlines and reminders within 120 days, soonest first', () {
      final cards = buildSeedCards(now);
      final river = buildTimeRiver(cards, now: now);
      expect(river.every((e) => e.days >= 0 && e.days <= riverDays), isTrue);
      for (var i = 1; i < river.length; i++) {
        expect(river[i].days >= river[i - 1].days, isTrue);
      }
      // Seed deadlines: 12, 26, 45 in range; 150 and 205 out.
      expect(river.where((e) => e.kind == RiverKind.deadline).length, 3);
      final tmo = river.firstWhere(
          (e) => e.card.id == 'sim-us-tmobile' && e.kind == RiverKind.reminder);
      expect(tmo.days, 12 - 3);
      expect(tmo.label, '提前 3 天提醒 · 去充值');
      // A deadline past 120 days still shows reminders inside the window.
      final far = cards.first.copyWith(
          nextDeadlineDate: addDays(dateOnly(now), 130), reminderOffsets: [30]);
      final farRiver = buildTimeRiver([far], now: now);
      expect(farRiver, hasLength(1));
      expect(farRiver.single.kind, RiverKind.reminder);
      expect(farRiver.single.days, 100);
    });

    testWidgets('Bento tile tapping an event focuses the card', (tester) async {
      await pumpApp(tester);
      expect(find.byKey(const Key('time-river')), findsOneWidget);
      final chip = find.byKey(const Key('river-sim-cn-cmcc-deadline-0'));
      expect(chip, findsOneWidget);
      await tester.tap(chip);
      await frames(tester, 10);
      expect(find.byKey(const Key('flip-card-sim-cn-cmcc')).hitTestable(),
          findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('phone layout shows the river tile too', (tester) async {
      await pumpApp(tester, phone: true);
      expect(find.byKey(const Key('time-river'), skipOffstage: false),
          findsOneWidget);
    });
  });

  group('smart entry', () {
    test('ICCID is extracted only when the Luhn check passes', () {
      final iccid = withCheckDigit('8986001234567890123');
      expect(extractIccid('ICCID: $iccid'), iccid);
      expect(extractIccid('89 8600 1234 5678 9012 3${iccid[19]}'), iccid);
      final bad = '${iccid.substring(0, 19)}${(int.parse(iccid[19]) + 1) % 10}';
      expect(extractIccid(bad), isNull);
      expect(extractIccid('hello'), isNull);
      // A 20-digit run that fails Luhn is not shortened to 19 digits.
      final body19 = withCheckDigit('898600123456789000');
      for (var d = 0; d < 10; d++) {
        if (!luhnValid('$body19$d')) {
          expect(extractIccid('$body19$d'), isNull);
          break;
        }
      }
    });

    test('SMS parser finds success, amount and validity date', () {
      final cn =
          parseRenewalSms('【中国移动】您已成功充值100.00元，当前余额120.5元，有效期至2027年06月30日。');
      expect(cn.success, isTrue);
      expect(cn.amount, 100);
      expect(cn.currency, 'CNY');
      expect(cn.deadline, DateTime(2027, 6, 30));

      final uk = parseRenewalSms(
          'Thanks! Your top-up successful: £10.00 added. Credit valid until 15/03/2027.');
      expect(uk.success, isTrue);
      expect(uk.amount, 10);
      expect(uk.currency, 'GBP');
      expect(uk.deadline, DateTime(2027, 3, 15));

      final hk = parseRenewalSms(
          'Club SIM: HK\$ 98 recharge successful, expiry date 2027-01-05');
      expect(hk.amount, 98);
      expect(hk.currency, 'HKD');
      expect(hk.deadline, DateTime(2027, 1, 5));

      expect(parseRenewalSms('明天见').isEmpty, isTrue);

      // Thousands separators and whole numbers only.
      expect(parseRenewalSms('チャージ1,000円が完了しました').amount, 1000);
      expect(parseRenewalSms('Top up successful: \$1,000.00').amount, 1000);
      // The balance is not the top-up amount.
      final bal =
          parseRenewalSms('Top-up successful: 10 USD. Your balance is \$25.');
      expect(bal.amount, 10);
      expect(bal.currency, 'USD');
      expect(parseRenewalSms('当前余额 120.5 元').amount, isNull);
      expect(parseRenewalSms('Top up successful: €10,50').amount, 10.5);
      final cnBal = parseRenewalSms('当前余额120元，充值成功￥50');
      expect(cnBal.amount, 50);
      expect(cnBal.currency, 'CNY');
      expect(parseRenewalSms('Balance:\n\$25\nTop up successful: \$10').amount,
          10);
      expect(parseRenewalSms('Balance: \$25; \$10 credit added.').amount, 10);
      expect(parseRenewalSms('当前余额120元，\n￥50 充值成功').amount, 50);
      expect(parseRenewalSms('余额120元，充值成功：\n￥50').amount, 50);
    });

    test('recordTopUp writes the confirmed amount and date', () {
      final c = buildSeedCards(now).first;
      final after =
          c.recordTopUp(amount: 10, deadline: DateTime(2027, 6, 30), now: now);
      expect(after.nextDeadlineDate, DateTime(2027, 6, 30));
      expect(after.events.first.type, CardEventType.topUp);
      expect(after.events.first.amount, 10);
      // Without a date the card's renewal rule decides.
      final ruled = c.recordTopUp(now: now);
      expect(ruled.nextDeadlineDate, c.checkIn(now: now).nextDeadlineDate);
    });

    testWidgets('SMS sheet pre-fills and writes only after confirming',
        (tester) async {
      await pumpApp(tester);
      await tester.tap(find.byKey(const Key('flip-sim-us-tmobile')));
      await frames(tester, 8);
      await tester.tap(find.byKey(const Key('sms-sim-us-tmobile')));
      await frames(tester, 8);
      await tester.enterText(find.byKey(const Key('sms-text')),
          'T-Mobile: Payment received \$3.00. Account valid until 12/31/2027.');
      await tester.pump();
      expect(find.text('3'), findsOneWidget); // amount field pre-filled
      // Nothing saved yet.
      expect(
          card(await vault(), 'sim-us-tmobile')
              .events
              .where((e) => e.note == '短信录入'),
          isEmpty);
      await tester.tap(find.byKey(const Key('sms-confirm')));
      await frames(tester, 8);
      final saved = card(await vault(), 'sim-us-tmobile');
      expect(saved.nextDeadlineDate, DateTime(2027, 12, 31));
      expect(saved.events.first.type, CardEventType.topUp);
      expect(saved.events.first.amount, 3);
    });

    testWidgets('SMS sheet: replaced text drops the old expiry',
        (tester) async {
      await tester.pumpWidget(
          MaterialApp(home: SmsRenewalPage(card: buildSeedCards(now).first)));
      await tester.enterText(
          find.byKey(const Key('sms-text')), '充值成功 50元 有效期至2028-01-01');
      await tester.pump();
      expect(find.text('2028-01-01'), findsWidgets);
      await tester.enterText(find.byKey(const Key('sms-text')), '充值成功');
      await tester.pump();
      expect(find.text('2028-01-01'), findsNothing);
      expect(find.textContaining('自动计算'), findsOneWidget);
      // A date can also be cleared by hand.
      await tester.enterText(
          find.byKey(const Key('sms-text')), '有效期至2028-01-01');
      await tester.pump();
      await tester.tap(find.byKey(const Key('sms-deadline-clear')));
      await tester.pump();
      expect(find.textContaining('自动计算'), findsOneWidget);
    });

    testWidgets('SMS sheet: backing out writes nothing', (tester) async {
      await pumpApp(tester);
      final before = card(await vault(), 'sim-us-tmobile');
      await tester.tap(find.byKey(const Key('flip-sim-us-tmobile')));
      await frames(tester, 8);
      await tester.tap(find.byKey(const Key('sms-sim-us-tmobile')));
      await frames(tester, 8);
      await tester.enterText(
          find.byKey(const Key('sms-text')), '充值成功 50元 有效期至2028-01-01');
      await tester.pageBack();
      await frames(tester, 8);
      expect(card(await vault(), 'sim-us-tmobile').nextDeadlineDate,
          before.nextDeadlineDate);
    });

    testWidgets('no camera platform: scan falls back to manual input',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(iccidScanSupported, isFalse);
      await tester.pumpWidget(const MaterialApp(home: SimFormPage()));
      await tester.ensureVisible(find.byKey(const Key('scan-iccid')));
      await tester.tap(find.byKey(const Key('scan-iccid')));
      await tester.pump();
      expect(find.text('当前平台不支持相机扫码，请手动输入 ICCID'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('field-iccid')), '8986');
      expect(find.text('8986'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('show number', () {
    test('QR payload keeps the dialable number', () {
      expect(ShowNumberPage.qrData('+44 7456 892011'), '+447456892011');
      expect(ShowNumberPage.qrData('138-0517-8842'), '13805178842');
    });

    testWidgets('card front opens full-screen number + QR, tap exits',
        (tester) async {
      await pumpApp(tester);
      await tester.tap(find.byKey(const Key('show-sim-gb-giffgaff')));
      await frames(tester, 8);
      expect(find.byKey(const Key('show-number-text')), findsOneWidget);
      expect(find.text('+44 7456 892011'), findsWidgets);
      expect(find.byKey(const Key('show-number-qr')), findsOneWidget);
      await tester.tap(find.byKey(const Key('show-number-exit')));
      await frames(tester, 8);
      expect(find.byKey(const Key('show-number-text')), findsNothing);
    });
  });

  group('reminder cadence', () {
    test('one VALARM per offset, wording by action type', () {
      final seeds = buildSeedCards(now);
      final tmo = card(seeds, 'sim-us-tmobile').copyWith(
          reminderOffsets: [30, 7, 1, 0],
          rechargeUrl: 'https://www.t-mobile.com/prepaid/refill');
      final gg = card(seeds, 'sim-gb-giffgaff');
      final ics = buildIcsCalendar([tmo, gg], now: now);
      expect('BEGIN:VALARM'.allMatches(ics).length, 4 + 1);
      for (final t in ['-P30D', '-P7D', '-P1D', 'PT0S', '-P3D']) {
        expect(ics, contains('TRIGGER:$t'));
      }
      final unfolded = ics.replaceAll('\r\n ', '');
      expect(unfolded, contains('去充值 https://www.t-mobile.com/prepaid/refill'));
      expect(unfolded, contains('URL:https://www.t-mobile.com/prepaid/refill'));
      expect(unfolded, contains('发短信/开 App 打卡'));
    });

    testWidgets('form edits offsets and tags', (tester) async {
      SimCard? result;
      final initial = buildSeedCards(now).first;
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => TextButton(
                  onPressed: () async => result = await Navigator.push(
                      context,
                      MaterialPageRoute<SimCard>(
                          builder: (_) => SimFormPage(initial: initial))),
                  child: const Text('open')))));
      await tester.tap(find.text('open'));
      await frames(tester, 8);
      for (final k in ['form-offset-30', 'form-offset-0', 'form-tag-主力']) {
        await tester.ensureVisible(find.byKey(Key(k)));
        await tester.tap(find.byKey(Key(k)));
        await tester.pump();
      }
      await tester.ensureVisible(find.byKey(const Key('save-card')));
      await tester.tap(find.byKey(const Key('save-card')));
      await frames(tester, 8);
      expect(result!.reminderOffsets, [30, 3, 0]);
      expect(result!.tags, ['主力']);
    });
  });

  group('tags', () {
    testWidgets('vault and river filter by tag; tags persist', (tester) async {
      final seeds = buildSeedCards(now);
      await SimRepository().save([
        for (final c in seeds)
          c.id == 'sim-gb-giffgaff' ? c.copyWith(tags: ['主力']) : c
      ]);
      await pumpApp(tester);
      await tester.ensureVisible(find.byKey(const Key('tag-主力')));
      await tester.tap(find.byKey(const Key('tag-主力')));
      await frames(tester);
      expect(
          find.byKey(const Key('flip-card-sim-gb-giffgaff')), findsOneWidget);
      expect(find.byKey(const Key('flip-card-sim-us-tmobile')), findsNothing);
      // The river follows the same filter.
      expect(find.byKey(const Key('river-sim-us-tmobile-deadline-0')),
          findsNothing);
      expect(find.byKey(const Key('river-sim-gb-giffgaff-deadline-0')),
          findsOneWidget);
      expect(card(await vault(), 'sim-gb-giffgaff').tags, ['主力']);
    });
  });

  group('privacy', () {
    test('masked ICS shows only the last four digits', () {
      final c = card(buildSeedCards(now), 'sim-gb-giffgaff');
      final plain = buildIcsCalendar([c], now: now);
      final masked = buildIcsCalendar([c], now: now, maskNumbers: true);
      expect(plain, contains('+44 7456 892011'));
      expect(masked, isNot(contains('7456 892011')));
      expect(masked, contains('尾号 2011'));
      expect(maskPhone('+86 138 0517 8842'), '尾号 8842');
    });

    testWidgets('settings switch defaults off and persists', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.byKey(const Key('open-settings')));
      await frames(tester, 8);
      final sw = find.byKey(const Key('privacy-switch'));
      expect(tester.widget<SwitchListTile>(sw).value, isFalse);
      await tester.tap(sw);
      await frames(tester, 8);
      expect(tester.widget<SwitchListTile>(sw).value, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('simvault.maskNumbers'), isTrue);
    });

    testWidgets('phone header has the settings entry', (tester) async {
      await pumpApp(tester, phone: true);
      expect(find.byKey(const Key('open-settings')), findsOneWidget);
    });
  });

  group('eSTK profile nickname', () {
    testWidgets('long-press a slot to name it; saved with the card',
        (tester) async {
      await pumpApp(tester);
      await tester.ensureVisible(find.byKey(const Key('slot-1')));
      await tester.longPress(find.byKey(const Key('slot-1')));
      await frames(tester, 8);
      await tester.enterText(
          find.byKey(const Key('slot-nickname-field')), '工作号');
      await tester.tap(find.byKey(const Key('slot-nickname-save')));
      await frames(tester, 8);
      expect(card(await vault(), 'sim-us-tmobile').profileName, '工作号');
      expect(find.text('#1 工作号'), findsOneWidget);
    });

    testWidgets('right-click opens the editor; empty slot explains',
        (tester) async {
      await pumpApp(tester);
      await tester.ensureVisible(find.byKey(const Key('slot-2')));
      await tester.tap(find.byKey(const Key('slot-2')),
          buttons: kSecondaryButton);
      await frames(tester, 8);
      expect(find.byKey(const Key('slot-nickname-field')), findsOneWidget);
      await tester.tap(find.text('取消'));
      await frames(tester, 8);
      await tester.longPress(find.byKey(const Key('slot-9')));
      await tester.pump();
      expect(find.textContaining('还没有 Profile'), findsOneWidget);
    });
  });
}
