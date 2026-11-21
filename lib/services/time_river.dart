import '../models/sim_card.dart';

enum RiverKind { deadline, reminder }

/// One point on the 120-day time river.
class RiverEvent {
  const RiverEvent(this.card, this.kind, this.date, this.days, this.offset);

  final SimCard card;
  final RiverKind kind;
  final DateTime date;

  /// Days from today.
  final int days;

  /// Reminder offset in days (0 for the deadline itself).
  final int offset;

  bool get isTopUp => card.keepAliveType == KeepAliveType.validity;

  String get label => switch (kind) {
        RiverKind.deadline => isTopUp ? '充值截止' : '打卡截止',
        RiverKind.reminder =>
          '${offset == 0 ? '当天' : '提前 $offset 天'}提醒 · ${isTopUp ? '去充值' : '去打卡'}',
      };
}

const riverDays = 120;

/// Deadlines and their reminder points from today to [days] days ahead,
/// soonest first. A lapsed deadline is shown at day 0.
List<RiverEvent> buildTimeRiver(List<SimCard> cards,
    {DateTime? now, int days = riverDays}) {
  final today = dateOnly(now ?? DateTime.now());
  final out = <RiverEvent>[];
  for (final c in cards) {
    final deadline = dateOnly(c.nextDeadlineDate);
    final d = remainingDays(deadline, now: today);
    // A deadline past the window can still have reminders inside it.
    if (d <= days) {
      out.add(RiverEvent(
          c, RiverKind.deadline, d < 0 ? today : deadline, d < 0 ? 0 : d, 0));
    }
    for (final o in c.reminderOffsets) {
      if (o == 0) continue;
      final at = d - o;
      if (at < 0 || at > days) continue;
      out.add(RiverEvent(c, RiverKind.reminder, addDays(deadline, -o), at, o));
    }
  }
  out.sort((a, b) {
    final byDay = a.days.compareTo(b.days);
    if (byDay != 0) return byDay;
    return a.kind.index.compareTo(b.kind.index);
  });
  return out;
}
