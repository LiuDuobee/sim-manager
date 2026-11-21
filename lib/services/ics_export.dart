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

/// One all-day VEVENT per card on its keep-alive deadline, with a VALARM
/// three days before.
String buildIcsCalendar(List<SimCard> cards, {DateTime? now}) {
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
    lines.addAll([
      'BEGIN:VEVENT',
      'UID:${card.id}-${_icsDate(start)}@simvault',
      'DTSTAMP:$stamp',
      'DTSTART;VALUE=DATE:${_icsDate(start)}',
      'DTEND;VALUE=DATE:${_icsDate(end)}',
      'SUMMARY:${_escape('【SIMVault 保号预警】${card.carrierName} (${card.phoneNumber})')}',
      'DESCRIPTION:${_escape('保号动作: ${card.keepAliveAction} | 存放位置: ${card.hostName} ${card.slotDetail} | 周期 ${card.keepAliveCycleDays} 天')}',
      'BEGIN:VALARM',
      'ACTION:DISPLAY',
      'DESCRIPTION:${_escape('${card.carrierName} 保号死线临近')}',
      'TRIGGER:-P3D',
      'END:VALARM',
      'END:VEVENT',
    ]);
  }
  lines.add('END:VCALENDAR');
  return '${lines.map(_fold).join('\r\n')}\r\n';
}
