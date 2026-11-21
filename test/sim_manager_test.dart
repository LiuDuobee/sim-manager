import 'package:flutter_test/flutter_test.dart';
import 'package:sim_manager/main.dart';
import 'package:sim_manager/services/estk_slots.dart';
import 'package:sim_manager/services/ics_export.dart';
import 'package:sim_manager/services/seed_cards.dart';

SimCard _card(String id,
        {MediaType media = MediaType.physical,
        LocationType location = LocationType.device,
        int? slot,
        int deadlineDays = 30,
        DateTime? now}) =>
    SimCard(
      id: id,
      carrierName: 'Carrier $id',
      phoneNumber: '+1 555 $id',
      countryCode: 'US',
      mediaType: media,
      locationType: location,
      estkSlotNumber: slot,
      keepAliveCycleDays: 90,
      nextDeadlineDate:
          dateOnly(now ?? DateTime.now()).add(Duration(days: deadlineDays)),
    );

void main() {
  final now = DateTime(2026, 11, 21, 15, 30);

  group('到期天数与紧急度', () {
    test('remainingDays counts calendar days, negative when overdue', () {
      expect(remainingDays(DateTime(2026, 11, 21), now: now), 0);
      expect(remainingDays(DateTime(2026, 12, 3), now: now), 12);
      expect(remainingDays(DateTime(2026, 11, 10), now: now), -11);
    });

    test('tiers: P1 ≤ 15, P2 ≤ 60, OK otherwise', () {
      expect(urgencyTierFor(-3), UrgencyTier.p1);
      expect(urgencyTierFor(15), UrgencyTier.p1);
      expect(urgencyTierFor(16), UrgencyTier.p2);
      expect(urgencyTierFor(60), UrgencyTier.p2);
      expect(urgencyTierFor(61), UrgencyTier.ok);
      expect(_card('1', deadlineDays: 12, now: now).urgency(now: now),
          UrgencyTier.p1);
    });
  });

  test('保号打卡 moves the deadline one cycle from today and logs it', () {
    final card = _card('1', deadlineDays: 2, now: now);
    final done = card.checkIn(now: now);
    expect(done.lastKeepAliveDate, DateTime(2026, 11, 21));
    expect(done.nextDeadlineDate,
        DateTime(2026, 11, 21).add(const Duration(days: 90)));
    expect(done.keepAliveLog, [DateTime(2026, 11, 21)]);
    expect(done.urgency(now: now), UrgencyTier.ok);
  });

  group('JSON 备份', () {
    test('round-trips every field', () {
      final cards = buildSeedCards(now);
      final decoded = SimCard.decodeList(SimCard.encodeList(cards));
      expect(decoded.map((c) => c.toJson()).toList(),
          cards.map((c) => c.toJson()).toList());
    });

    test('redaction strips PIN/PUK/LPA but keeps ICCID', () {
      final json = SimCard.encodeList(buildSeedCards(now), redactSecrets: true);
      final decoded = SimCard.decodeList(json);
      expect(
          decoded.every(
              (c) => c.pin1.isEmpty && c.puk1.isEmpty && c.esimLpaCode.isEmpty),
          isTrue);
      expect(decoded.first.iccid, isNotEmpty);
    });

    test('accepts {cards: [...]} and legacy v1 records', () {
      final cards = SimCard.decodeList(
          '{"cards":[{"id":"x","operatorName":"Old","type":"esim","nextRenewalDate":"2027-01-01T00:00:00.000","monthlyFee":5}]}');
      expect(cards.single.carrierName, 'Old');
      expect(cards.single.mediaType, MediaType.esim);
      expect(cards.single.cycleCost, 5);
    });

    test('rejects malformed input', () {
      expect(() => SimCard.decodeList('{"foo":1}'), throwsFormatException);
    });
  });

  group('15 槽 eSTK 矩阵', () {
    test('occupancy follows the number of programmable-medium cards', () {
      expect(layoutEstkSlots(buildSeedCards(now)).usageLabel, '占用 3 / 15 槽位');
      final cards = [
        _card('a', media: MediaType.programmable, slot: 4),
        _card('b', location: LocationType.smartCard, media: MediaType.esim),
        _card('c'),
        _card('d', media: MediaType.programmable, slot: 4),
      ];
      final layout = layoutEstkSlots(cards);
      expect(layout.occupied, 3);
      expect(layout.slots[4]!.id, 'a');
      expect(layout.slots[1]!.id, 'b');
      expect(layout.slots[2]!.id, 'd');
      expect(layout.slots.values.any((c) => c.id == 'c'), isFalse);
    });

    test('more than 15 programmable cards overflow', () {
      final cards = [
        for (var i = 0; i < 17; i++) _card('$i', media: MediaType.programmable)
      ];
      final layout = layoutEstkSlots(cards);
      expect(layout.occupied, 15);
      expect(layout.overflow.length, 2);
    });
  });

  test('ICS export emits RFC 5545 all-day events with alarms', () {
    final cards = buildSeedCards(now).take(2).toList();
    final ics = buildIcsCalendar(cards, now: now);
    expect(ics, startsWith('BEGIN:VCALENDAR\r\nVERSION:2.0\r\n'));
    expect(ics, endsWith('END:VCALENDAR\r\n'));
    expect('BEGIN:VEVENT'.allMatches(ics).length, 2);
    expect(ics, contains('DTSTART;VALUE=DATE:20261203'));
    expect(ics, contains('DTEND;VALUE=DATE:20261204'));
    expect(ics, contains('UID:sim-us-tmobile-20261203@simvault'));
    expect(ics, contains('TRIGGER:-P3D'));
    for (final line in ics.split('\r\n')) {
      expect(line.codeUnits.length <= 75 * 3, isTrue);
    }
  });
}
