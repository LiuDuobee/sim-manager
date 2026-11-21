import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sim_manager/features/cards/region_flag.dart';
import 'package:sim_manager/features/globe/topojson.dart';
import 'package:sim_manager/features/hud/hud_stage.dart';
import 'package:sim_manager/features/hud/hud_theme.dart';
import 'package:sim_manager/main.dart';
import 'package:sim_manager/pages/home_page.dart';
import 'package:sim_manager/pages/sim_form_page.dart';
import 'package:sim_manager/services/carrier_presets.dart';
import 'package:sim_manager/services/ics_export.dart';
import 'package:sim_manager/services/region_catalog.dart';
import 'package:sim_manager/services/seed_cards.dart';
import 'package:sim_manager/services/sim_repository.dart';
import 'package:sim_manager/services/time_river.dart';

/// v3.4.0 PR-A: region / carrier / currency pickers, plan type, card kind,
/// keep-alive cycle chips, region flag + accent stripe.
void main() {
  final now = DateTime(2026, 11, 21);
  final today = dateOnly(now);

  SimCard card(String id,
          {PlanType plan = PlanType.prepaid,
          bool rule = true,
          CardKind kind = CardKind.voice,
          int deadlineIn = 10,
          DateTime? planEnd}) =>
      SimCard(
        id: id,
        carrierName: id,
        phoneNumber: '+1 555 0100',
        countryCode: 'US',
        mediaType: MediaType.physical,
        nextDeadlineDate: addDays(today, deadlineIn),
        planType: plan,
        keepAliveEnabled: rule,
        kind: kind,
        planEndDate: planEnd,
      );

  group('region catalog', () {
    test('中国 first with 大陆/香港/澳门/台湾; 台湾 only as a Chinese region', () {
      expect(allRegions.take(4).map((r) => r.code), ['CN', 'HK', 'MO', 'TW']);
      expect(allRegions.take(4).map((r) => r.name),
          ['中国大陆', '中国香港', '中国澳门', '中国台湾']);
      expect(allRegions.where((r) => r.code == 'TW'), hasLength(1));
      expect(popularRegions.any((r) => r.code == 'TW'), isFalse);
      expect(otherRegions.any((r) => r.code == 'TW'), isFalse);
      expect(regionFor('TW').name, '中国台湾');
    });

    test('flags: 台湾 uses 🇨🇳, 香港 🇭🇰, 澳门 🇲🇴', () {
      expect(flagEmoji('TW'), '🇨🇳');
      expect(flagEmoji('CN'), '🇨🇳');
      expect(flagEmoji('HK'), '🇭🇰');
      expect(flagEmoji('MO'), '🇲🇴');
      expect(flagEmoji('gb'), '🇬🇧');
    });

    test('popular countries come next, the rest A–Z by code', () {
      expect(
          popularRegions.take(4).map((r) => r.code), ['GB', 'US', 'JP', 'SG']);
      final codes = otherRegions.map((r) => r.code).toList();
      expect(codes, [...codes]..sort());
      expect(
          allRegions.map((r) => r.code).toSet(), hasLength(allRegions.length));
    });

    test('search by name or code keeps the hierarchy and finds 台湾', () {
      expect(searchRegions('台湾').single.code, 'TW');
      expect(searchRegions('中国').map((r) => r.code),
          containsAll(['CN', 'HK', 'MO', 'TW']));
      expect(searchRegions('gb').single.code, 'GB');
      expect(regionFor('ZZ').name, 'ZZ');
    });

    test('carriers per region match the brief', () {
      List<String> names(String c) =>
          regionFor(c).carriers.map((x) => x.name).toList();
      expect(names('CN'), ['中国移动', '中国联通', '中国电信', '中国广电']);
      expect(names('HK'),
          ['csl', '3HK', 'SmarTone', '中国移动香港', 'Club SIM', 'SoSIM', 'birdie']);
      expect(names('MO'), ['CTM', '3澳门', '中国电信澳门']);
      expect(names('TW'), ['中华电信', '远传', '台湾大哥大']);
      expect(names('GB'),
          ['giffgaff', 'EE', 'Vodafone', 'O2', 'Three', 'VOXI', 'Lebara']);
      expect(names('US'), [
        'T-Mobile',
        'AT&T',
        'Verizon',
        'Ultra Mobile',
        'Google Fi',
        'Mint',
        'Tello'
      ]);
      expect(names('JP'), [
        'povo',
        '楽天',
        'ahamo',
        'LINEMO',
        'IIJmio',
        'docomo',
        'au',
        'SoftBank'
      ]);
      expect(names('SG'), ['Singtel', 'StarHub', 'M1', 'SIMBA']);
    });

    test('carriers with rules link to the phase-1 rule library unchanged', () {
      final linked = {
        for (final r in allRegions)
          for (final c in r.carriers)
            if (c.presetId.isNotEmpty) c.presetId
      };
      for (final id in linked) {
        expect(presetById(id), isNotNull, reason: id);
      }
      expect(presetById('giffgaff')!.cycleDays, 180);
      expect(presetById('club-sim')!.cycleDays, 365);
    });

    test('currency defaults per region and searchable currencies', () {
      expect(regionFor('HK').currency, 'HKD');
      expect(regionFor('TW').currency, 'TWD');
      expect(regionFor('CN').currency, 'CNY');
      expect(regionFor('MO').currency, 'MOP');
      expect(regionFor('JP').currency, 'JPY');
      expect(searchCurrencies('港').single.code, 'HKD');
      expect(searchCurrencies('twd').single.symbol, 'NT\$');
      expect(currencyFor('gbp')!.name, '英镑');
    });

    test('source presets cover travel platforms and domestic channels', () {
      expect(travelSources, containsAll(['Airalo', 'Holafly', 'Klook 客路']));
      expect(travelSources, hasLength(24));
      expect(domesticDataSources, ['运营商官方', '电商平台', '线下卡商']);
    });
  });

  test('every picker currency has a CNY estimate rate', () {
    for (final c in currencies) {
      expect(exchangeRatesToCny, contains(c.code), reason: c.code);
    }
    for (final r in allRegions) {
      expect(exchangeRatesToCny, contains(r.currency), reason: r.code);
    }
  });

  test('passport edit diff names the new fields', () {
    final a = card('a');
    final b = a.copyWith(
        planType: PlanType.postpaid,
        keepAliveEnabled: false,
        kind: CardKind.travel,
        source: 'Airalo',
        dataUnlimited: true,
        planDays: () => 7);
    expect(describeEdit(a, b),
        ['预付/上台', '保号规则开关', '用途类型', '来源平台', '总流量', '套餐有效期']);
  });

  test('globe node ignores rule-less cards for urgency', () {
    final overdue = SimCard(
      id: 'p',
      carrierName: 'csl',
      phoneNumber: '',
      countryCode: 'HK',
      mediaType: MediaType.physical,
      nextDeadlineDate: DateTime(2000),
      planType: PlanType.postpaid,
      keepAliveEnabled: false,
    );
    final node = buildGlobeNodes([overdue], const []).single;
    expect(node.color, HudPalette.dark.tierColor(UrgencyTier.ok));
  });

  group('accent stripe contrast', () {
    test('every region accent keeps ≥ 3:1 on card face and both themes', () {
      for (final r in [...allRegions, regionFor('ZZ')]) {
        for (final bg in [
          const Color(0xFF0F172A),
          HudPalette.dark.bg,
          HudPalette.light.bg,
          Colors.white,
        ]) {
          expect(contrastRatio(regionAccent(r.code, bg), bg),
              greaterThanOrEqualTo(3),
              reason: '${r.code} on $bg');
        }
      }
    });
  });

  group('model', () {
    test('old JSON migrates to prepaid voice card with its rule on', () {
      final json = card('a').toJson()
        ..remove('planType')
        ..remove('keepAliveEnabled')
        ..remove('kind')
        ..remove('source')
        ..remove('dataTotalGb')
        ..remove('dataUnlimited')
        ..remove('planStartDate')
        ..remove('planDays')
        ..remove('planEndDate')
        ..remove('customKind');
      final c = SimCard.fromJson(json);
      expect(c.planType, PlanType.prepaid);
      expect(c.keepAliveEnabled, isTrue);
      expect(c.kind, CardKind.voice);
      expect(c.dataTotalGb, isNull);
      expect(c.hasDeadline, isTrue);
    });

    test('new fields round-trip through JSON', () {
      final c = card('t', kind: CardKind.travel, rule: false).copyWith(
          source: 'Airalo',
          dataTotalGb: () => 10,
          planStartDate: () => today,
          planDays: () => 7,
          planType: PlanType.postpaid);
      final back = SimCard.fromJson(
          jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>);
      expect(back.toJson(), c.toJson());
      expect(back.planExpiry, addDays(today, 7));
      final other = SimCard.fromJson(
          {...card('o').toJson(), 'kind': 'Other', 'customKind': '车载卡'});
      expect(other.kindLabel, '车载卡');
    });

    test('invalid data volume / plan days are rejected, not zeroed', () {
      expect(() => SimCard.fromJson({...card('a').toJson(), 'dataTotalGb': -1}),
          throwsFormatException);
      expect(() => SimCard.fromJson({...card('a').toJson(), 'planDays': 0}),
          throwsFormatException);
    });

    test('postpaid without a rule has no deadline anywhere', () {
      final post =
          card('post', plan: PlanType.postpaid, rule: false, deadlineIn: 1);
      final pre = card('pre', deadlineIn: 20);
      expect(post.hasDeadline, isFalse);
      expect(post.trackedUrgency(now: now), isNull);
      expect(buildTimeRiver([post, pre], now: now).map((e) => e.card.id),
          everyElement('pre'));
      expect(smartSummary([post, pre], now: now), contains('pre'));
      expect(smartSummary([post], now: now), '没有需要保号或即将到期的卡');
      expect(buildIcsCalendar([post], now: now), isNot(contains('VEVENT')));
    });

    test('postpaid with a rule added by hand keeps counting down', () {
      final c = card('p', plan: PlanType.postpaid, deadlineIn: 5);
      expect(c.trackedDays(now: now), 5);
      expect(c.trackedUrgency(now: now), UrgencyTier.p1);
    });

    test('travel card counts down to its plan expiry, river shows it', () {
      final c = card('trip',
          kind: CardKind.travel,
          rule: false,
          deadlineIn: 300,
          planEnd: addDays(today, 6));
      expect(c.tracksPlanExpiry, isTrue);
      expect(c.daysRemaining(now: now), 6);
      final river = buildTimeRiver([c], now: now);
      expect(river.single.label, '套餐到期');
      expect(river.single.days, 6);
    });
  });

  group('form', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<void> frames(WidgetTester tester, [int n = 6]) async {
      for (var i = 0; i < n; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<SimCard? Function()> openForm(WidgetTester tester,
        {SimCard? initial}) async {
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
                          builder: (_) => SimFormPage(initial: initial))),
                  child: const Text('open')))));
      await tester.tap(find.text('open'));
      await frames(tester, 8);
      return () => result;
    }

    Future<void> tapKey(WidgetTester tester, String key) async {
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.tap(find.byKey(Key(key)));
      await frames(tester);
    }

    Future<void> choose(WidgetTester tester, String key, String item) async {
      await tapKey(tester, key);
      await tester.tap(find.text(item).last);
      await frames(tester);
    }

    String text(WidgetTester tester, String key) =>
        tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;

    testWidgets('region picker fills currency and default carrier',
        (tester) async {
      final result = await openForm(tester);
      await tapKey(tester, 'pick-region');
      expect(find.byKey(const Key('region-TW')), findsOneWidget);
      await tester.tap(find.byKey(const Key('region-HK')));
      await frames(tester);
      expect(text(tester, 'field-country'), 'HK');
      expect(text(tester, 'field-currency'), 'HKD');
      expect(text(tester, 'field-carrier'), 'csl');
      expect(find.byKey(const Key('carrier-chip-birdie')), findsOneWidget);

      // A rule-bearing carrier brings its phase-1 rule (Club SIM 365 days).
      await tapKey(tester, 'carrier-chip-Club SIM');
      expect(text(tester, 'field-carrier'), 'Club SIM');
      expect(text(tester, 'field-cycle'), '365');
      expect(find.text('自定义 · 365 天'), findsOneWidget);

      // Validity rules offer cycle chips plus custom days.
      await tapKey(tester, 'cycle-chip-90');
      expect(text(tester, 'field-cycle'), '90');

      // Currency stays editable through its own picker.
      await tapKey(tester, 'pick-currency');
      await tester.enterText(find.byKey(const Key('currency-search')), '新台币');
      await frames(tester);
      await tester.tap(find.byKey(const Key('currency-TWD')));
      await frames(tester);
      expect(text(tester, 'field-currency'), 'TWD');

      await tapKey(tester, 'save-card');
      final c = result()!;
      expect(c.countryCode, 'HK');
      expect(c.carrierPresetId, 'club-sim');
      expect(c.keepAliveCycleDays, 90);
      expect(c.currency, 'TWD');
      expect(c.planType, PlanType.prepaid);
    });

    testWidgets('picker accepts a custom code; 台湾 sits under 中国',
        (tester) async {
      await openForm(tester);
      await tapKey(tester, 'pick-region');
      await tester.enterText(find.byKey(const Key('region-search')), '台湾');
      await frames(tester);
      expect(find.text('中国'), findsOneWidget);
      expect(find.byKey(const Key('region-TW')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('region-search')), 'xk');
      await frames(tester);
      await tester.tap(find.byKey(const Key('region-custom')));
      await frames(tester);
      expect(text(tester, 'field-country'), 'XK');
    });

    testWidgets('postpaid starts without a rule; it can be added back',
        (tester) async {
      final result = await openForm(tester);
      await tester.enterText(find.byKey(const Key('field-carrier')), 'csl');
      await choose(tester, 'field-plan-type', '上台（合约）');
      expect(find.byKey(const Key('field-cycle')), findsNothing);
      await tapKey(tester, 'save-card');
      expect(result()!.planType, PlanType.postpaid);
      expect(result()!.keepAliveEnabled, isFalse);
    });

    testWidgets('a cleared cycle field does not block a rule-less save',
        (tester) async {
      final result = await openForm(tester);
      await tester.enterText(find.byKey(const Key('field-carrier')), 'EE');
      await tester.enterText(find.byKey(const Key('field-cycle')), '');
      await tapKey(tester, 'field-ka-enabled');
      await tapKey(tester, 'save-card');
      expect(result()!.keepAliveEnabled, isFalse);
      expect(result()!.keepAliveCycleDays, 180);
    });

    testWidgets('postpaid rule switched back on is saved', (tester) async {
      final result = await openForm(tester);
      await tester.enterText(find.byKey(const Key('field-carrier')), 'EE');
      await choose(tester, 'field-plan-type', '上台（合约）');
      await tapKey(tester, 'field-ka-enabled');
      expect(find.byKey(const Key('field-cycle')), findsOneWidget);
      await tapKey(tester, 'save-card');
      expect(result()!.keepAliveEnabled, isTrue);
    });

    testWidgets('travel card: source presets, volume, plan validity',
        (tester) async {
      final result = await openForm(tester);
      await tester.enterText(find.byKey(const Key('field-carrier')), 'Ubigi');
      await choose(tester, 'field-kind', '旅游卡');
      await tapKey(tester, 'source-chip-Airalo');
      await tester.enterText(find.byKey(const Key('field-data-gb')), '-3');
      await tapKey(tester, 'save-card');
      expect(result(), isNull);
      expect(find.text('非负数字'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('field-data-gb')), '5');
      await tester.enterText(find.byKey(const Key('field-plan-days')), '15');
      await tapKey(tester, 'save-card');
      final c = result()!;
      expect(c.kind, CardKind.travel);
      expect(c.source, 'Airalo');
      expect(c.dataTotalGb, 5);
      expect(c.planDays, 15);
      expect(c.keepAliveEnabled, isFalse);
    });

    testWidgets('picking a region keeps a data card rule-less',
        (tester) async {
      final result = await openForm(tester);
      await choose(tester, 'field-kind', '旅游卡');
      await tapKey(tester, 'pick-region');
      await tester.tap(find.byKey(const Key('region-JP')));
      await frames(tester);
      expect(text(tester, 'field-carrier'), 'povo');
      expect(find.byKey(const Key('field-cycle')), findsNothing);
      await tester.enterText(find.byKey(const Key('field-plan-days')), '5');
      await tapKey(tester, 'save-card');
      expect(result()!.keepAliveEnabled, isFalse);
      expect(result()!.carrierPresetId, 'povo2');
    });

    testWidgets('other kind takes a custom name and keeps its rule',
        (tester) async {
      final result = await openForm(tester);
      await tester.enterText(find.byKey(const Key('field-carrier')), 'X');
      await choose(tester, 'field-kind', '其他');
      await tester.enterText(find.byKey(const Key('field-custom-kind')), '车载卡');
      await tapKey(tester, 'save-card');
      expect(result()!.kindLabel, '车载卡');
      expect(result()!.keepAliveEnabled, isTrue);
    });
  });

  group('home page', () {
    final atlas = decodeWorldAtlas(
        File('assets/geo/countries-110m.json').readAsStringSync());

    Future<void> frames(WidgetTester tester, [int n = 4]) async {
      for (var i = 0; i < n; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('flag, stripe, 上台 / kind badges and filters', (tester) async {
      final seeds = buildSeedCards(now);
      await SimRepository().save([
        for (final c in seeds)
          switch (c.id) {
            'sim-hk-clubsim' =>
              c.copyWith(planType: PlanType.postpaid, keepAliveEnabled: false),
            'sim-jp-rakuten' => c.copyWith(
                kind: CardKind.travel,
                keepAliveEnabled: false,
                planEndDate: () => addDays(dateOnly(DateTime.now()), 9)),
            _ => c,
          }
      ]);
      tester.view.physicalSize = const Size(1600, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          SimVaultApp(home: HomePage(atlasLoader: () async => atlas)));
      await tester.pump();
      await frames(tester, 2);

      expect(find.byKey(const Key('flag-sim-hk-clubsim')), findsOneWidget);
      expect(find.byKey(const Key('region-stripe-HK')), findsWidgets);
      expect(find.byKey(const Key('postpaid-sim-hk-clubsim')), findsOneWidget);
      expect(find.byKey(const Key('kind-sim-jp-rakuten')), findsOneWidget);
      expect(find.byKey(const Key('postpaid-sim-us-tmobile')), findsNothing);
      expect(find.text('上台合约 · 无保号规则'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('plan-filter-postpaid')));
      await tester.tap(find.byKey(const Key('plan-filter-postpaid')));
      await frames(tester);
      expect(find.byKey(const Key('flip-card-sim-hk-clubsim')), findsOneWidget);
      expect(find.byKey(const Key('flip-card-sim-us-tmobile')), findsNothing);

      await tester.tap(find.byKey(const Key('plan-filter-postpaid')));
      await frames(tester);
      await tester.ensureVisible(find.byKey(const Key('kind-filter-travel')));
      await tester.tap(find.byKey(const Key('kind-filter-travel')));
      await frames(tester);
      expect(find.byKey(const Key('flip-card-sim-jp-rakuten')), findsOneWidget);
      expect(find.byKey(const Key('flip-card-sim-hk-clubsim')), findsNothing);
      // The travel card's plan expiry is on the time river.
      expect(find.byKey(const Key('river-sim-jp-rakuten-deadline-0')),
          findsOneWidget);
    });
  });
}
