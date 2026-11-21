import 'dart:convert';

import '../models/sim_card.dart';

String _icsDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

String _icsStamp(DateTime d) {
  final u = d.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${_icsDate(u)}T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
}

String _escape(String v) => v
    .replaceAll(r'\', r'\\')
    .replaceAll(';', r'\;')
    .replaceAll(',', r'\,')
    .replaceAll('\n', r'\n');

/// RFC 5545 §3.1 line folding at 75 octets without splitting UTF-8 chars.
String _fold(String line) {
  final out = StringBuffer();
  var octets = 0;
  for (final rune in line.runes) {
    final ch = String.fromCharCode(rune);
    final size = utf8.encode(ch).length;
    if (octets + size > 75) {
      out.write('\r\n ');
      octets = 1;
    }
    out.write(ch);
    octets += size;
  }
  return out.toString();
}

/// One all-day VEVENT per card on its keep-alive deadline, with one VALARM
/// per reminder offset. Alarm text names the next action: activity cards
/// say how to check in, validity cards say to top up and link the carrier's
/// recharge page. [maskNumbers] keeps only the last four digits.
String buildIcsCalendar(List<SimCard> cards,
    {DateTime? now, bool maskNumbers = false}) {
  final stamp = _icsStamp(now ?? DateTime.now());
  final lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//SIMVault//Global SIM Keep-Alive Radar//CN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'X-WR-CALNAME:SIMVault 保号提醒',
  ];
  for (final card in cards) {
    final start = dateOnly(card.nextDeadlineDate);
    final end = addDays(start, 1);
    final number = maskNumbers ? maskPhone(card.phoneNumber) : card.phoneNumber;
    final topUp = card.keepAliveType == KeepAliveType.validity;
    final action =
        card.keepAliveAction.isEmpty ? '' : '：${card.keepAliveAction}';
    final todo = topUp
        ? '去充值${card.rechargeUrl.isEmpty ? action : ' ${card.rechargeUrl}'}'
        : '发短信/开 App 打卡$action';
    lines.addAll([
      'BEGIN:VEVENT',
      'UID:${card.id}-${_icsDate(start)}@simvault',
      'DTSTAMP:$stamp',
      'DTSTART;VALUE=DATE:${_icsDate(start)}',
      'DTEND;VALUE=DATE:${_icsDate(end)}',
      'SUMMARY:${_escape('【SIMVault 保号预警】${card.carrierName}${number.isEmpty ? '' : ' ($number)'}')}',
      'DESCRIPTION:${_escape('${card.keepAliveType.verb} · $todo | 保号动作: ${card.keepAliveAction} | 存放位置: ${card.hostName} ${card.slotDetail} | 周期 ${card.keepAliveCycleDays} 天')}',
      if (topUp && card.rechargeUrl.isNotEmpty) 'URL:${card.rechargeUrl}',
      for (final o in card.reminderOffsets) ...[
        'BEGIN:VALARM',
        'ACTION:DISPLAY',
        'DESCRIPTION:${_escape('${card.carrierName}${o == 0 ? ' 今天' : ' $o 天后'}保号死线 · $todo')}',
        'TRIGGER:${o == 0 ? 'PT0S' : '-P${o}D'}',
        'END:VALARM',
      ],
      'END:VEVENT',
    ]);
  }
  lines.add('END:VCALENDAR');
  return '${lines.map(_fold).join('\r\n')}\r\n';
}
