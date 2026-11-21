import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/sim_card.dart';
import '../hud/hud_theme.dart';

const chamferSize = 28.0;
const flipDuration = Duration(milliseconds: 650);
const flipCurve = Cubic(0.22, 1, 0.36, 1);

/// Equivalent of `clip-path: polygon(0 0, calc(100% - 28px) 0, 100% 28px,
/// 100% 100%, 0 100%)`: a true 45° cut on the top-right corner.
Path chamferPath(Size size, {double cut = chamferSize, double radius = 18}) {
  final w = size.width, h = size.height;
  return Path()
    ..moveTo(radius, 0)
    ..lineTo(w - cut, 0)
    ..lineTo(w, cut)
    ..lineTo(w, h - radius)
    ..arcToPoint(Offset(w - radius, h), radius: Radius.circular(radius))
    ..lineTo(radius, h)
    ..arcToPoint(Offset(0, h - radius), radius: Radius.circular(radius))
    ..lineTo(0, radius)
    ..arcToPoint(Offset(radius, 0), radius: Radius.circular(radius))
    ..close();
}

class ChamferClipper extends CustomClipper<Path> {
  const ChamferClipper();

  @override
  Path getClip(Size size) => chamferPath(size);

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _ChamferBorderPainter extends CustomPainter {
  const _ChamferBorderPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
      chamferPath(size),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = color);

  @override
  bool shouldRepaint(covariant _ChamferBorderPainter old) => old.color != color;
}

List<Color> cardGradient(String countryCode) => switch (countryCode) {
      'US' => const [Color(0xFF831843), Color(0xFF500724), Color(0xFF0F172A)],
      'CN' => const [Color(0xFF1E3A8A), Color(0xFF172554), Color(0xFF0F172A)],
      'GB' => const [Color(0xFF1F2937), Color(0xFF111827), Color(0xFF3B0764)],
      'HK' => const [Color(0xFF4C1D95), Color(0xFF2E1065), Color(0xFF0F172A)],
      'JP' => const [Color(0xFF991B1B), Color(0xFF450A0A), Color(0xFF0F172A)],
      _ => const [Color(0xFF0F766E), Color(0xFF134E4A), Color(0xFF0F172A)],
    };

/// Physical SIM card with a 45° chamfer that flips in 3D (perspective +
/// rotateY 180°, 650 ms). Only the face toward the viewer is built, and the
/// back is pre-rotated by π so it never shows mirrored.
class FlipSimCard extends StatefulWidget {
  const FlipSimCard({
    super.key,
    required this.card,
    required this.onCheckIn,
    required this.onEdit,
    required this.onDelete,
    required this.onExportIcs,
    this.highlighted = false,
  });

  final SimCard card;
  final VoidCallback onCheckIn;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onExportIcs;
  final bool highlighted;

  @override
  State<FlipSimCard> createState() => FlipSimCardState();
}

class FlipSimCardState extends State<FlipSimCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flip =
      AnimationController(vsync: this, duration: flipDuration);
  late final Animation<double> _angle = CurvedAnimation(
      parent: _flip, curve: flipCurve, reverseCurve: flipCurve.flipped);
  bool _secretsVisible = false;

  bool get isFlipped =>
      _flip.status == AnimationStatus.forward ||
      _flip.status == AnimationStatus.completed;

  void toggle() => isFlipped ? _flip.reverse() : _flip.forward();

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final border =
        widget.highlighted ? Hud.amber : Colors.white.withValues(alpha: .14);
    return GestureDetector(
      onTap: toggle,
      child: AnimatedBuilder(
        animation: _angle,
        builder: (context, _) {
          final angle = _angle.value * math.pi;
          final showFront = angle <= math.pi / 2;
          final face = showFront
              ? _Front(
                  key: Key('card-front-${card.id}'),
                  card: card,
                  onCheckIn: widget.onCheckIn,
                  onFlip: toggle)
              : Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.rotationY(math.pi),
                  child: _Back(
                    key: Key('card-back-${card.id}'),
                    card: card,
                    secretsVisible: _secretsVisible,
                    onToggleSecrets: () =>
                        setState(() => _secretsVisible = !_secretsVisible),
                    onCheckIn: widget.onCheckIn,
                    onExportIcs: widget.onExportIcs,
                    onEdit: widget.onEdit,
                    onDelete: widget.onDelete,
                    onFlip: toggle,
                  ),
                );
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 1 / 1200)
              ..rotateY(angle),
            child: CustomPaint(
              foregroundPainter: _ChamferBorderPainter(border),
              child: ClipPath(
                clipper: const ChamferClipper(),
                child: Container(
                  height: Hud.isCompact(context) ? 336 : 270,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: showFront
                          ? cardGradient(card.countryCode)
                          : const [Color(0xFF0F172A), Color(0xFF020617)],
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: face,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SimChip extends StatelessWidget {
  const _SimChip();

  @override
  Widget build(BuildContext context) => Container(
        width: 42,
        height: 32,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          gradient: const LinearGradient(colors: [
            Color(0xFFFDE68A),
            Color(0xFFD97706),
            Color(0xFFFCD34D)
          ]),
        ),
        child: CustomPaint(painter: _ChipLinesPainter()),
      );
}

class _ChipLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0x66432A03)
      ..strokeWidth = 1;
    canvas.drawLine(
        Offset(0, size.height / 3), Offset(size.width, size.height / 3), p);
    canvas.drawLine(Offset(0, size.height * 2 / 3),
        Offset(size.width, size.height * 2 / 3), p);
    canvas.drawLine(
        Offset(size.width / 2, 0), Offset(size.width / 2, size.height), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.color = Colors.white});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .3),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: .35)),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 10.5, color: color, fontWeight: FontWeight.w600)),
      );
}

Widget _smallButton(String label, VoidCallback onTap,
        {Key? key, Color color = Colors.white}) =>
    _SmallButton(label, onTap, key: key, color: color);

/// Card action chip. On phones the visible chip stays compact but the touch
/// target grows to at least 48×48dp.
class _SmallButton extends StatelessWidget {
  const _SmallButton(this.label, this.onTap,
      {super.key, this.color = Colors.white});

  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final compact = Hud.isCompact(context);
    final chip = Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 10, vertical: compact ? 8 : 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(compact ? 10 : 8),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: compact ? 12 : 11,
              color: color,
              fontWeight: FontWeight.w600)),
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: TapTarget(enabled: compact, child: chip),
    );
  }
}

class _Front extends StatelessWidget {
  const _Front(
      {super.key,
      required this.card,
      required this.onCheckIn,
      required this.onFlip});

  final SimCard card;
  final VoidCallback onCheckIn;
  final VoidCallback onFlip;

  @override
  Widget build(BuildContext context) {
    final days = card.daysRemaining();
    final tier = urgencyTierFor(days);
    final color = Hud.tierColor(tier);
    final progress = (days / math.max(card.keepAliveCycleDays, 1))
        .clamp(0.0, 1.0)
        .toDouble();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(right: chamferSize - 6),
        child: Row(children: [
          Text(card.countryCode,
              style: Hud.mono.copyWith(
                  fontSize: 12, fontWeight: FontWeight.w800, color: Hud.muted)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(card.carrierName,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ),
          _Tag(card.mediaType.label, color: Hud.mediaColor(card.mediaType)),
          const SizedBox(width: 6),
          _Tag(card.isActive ? 'ONLINE' : 'STORED',
              color: card.isActive ? Hud.emerald : Hud.sky),
        ]),
      ),
      Text(card.planName,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: Hud.muted)),
      const SizedBox(height: 14),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _SimChip(),
        const SizedBox(width: 12),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topRight,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(card.phoneNumber.isEmpty ? '未录入号码' : card.phoneNumber,
                  style: Hud.mono
                      .copyWith(fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                  '余额 ${card.balance.toStringAsFixed(card.balance % 1 == 0 ? 0 : 2)} ${card.currency} · ≈ ¥${card.monthlyCny.toStringAsFixed(1)}/月',
                  style: Hud.mono.copyWith(fontSize: 10.5, color: Hud.muted)),
            ]),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 6, runSpacing: 4, children: [
        _Tag('${card.hostName} · ${card.slotDetail}'),
        if (card.estkSlotNumber != null)
          _Tag('eSTK #${card.estkSlotNumber}', color: Hud.amber),
      ]),
      const Spacer(),
      Row(children: [
        Expanded(
          child: Text(
              '到期 ${DateFormat('yyyy-MM-dd').format(card.nextDeadlineDate)}',
              style: Hud.mono.copyWith(fontSize: 11, color: Hud.muted)),
        ),
        Text('${tier.code} · ${days < 0 ? '已过期 ${-days}' : '剩 $days'} 天',
            key: Key('days-${card.id}'),
            style: Hud.mono.copyWith(
                fontSize: 11.5, fontWeight: FontWeight.w800, color: color)),
      ]),
      const SizedBox(height: 5),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: progress,
          minHeight: 4,
          color: color,
          backgroundColor: Colors.white.withValues(alpha: .08),
        ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        _smallButton('保号打卡', onCheckIn,
            key: Key('checkin-${card.id}'), color: Hud.emerald),
        const Spacer(),
        _smallButton('翻面 ↻', onFlip, key: Key('flip-${card.id}')),
      ]),
    ]);
  }
}

class _Back extends StatelessWidget {
  const _Back({
    super.key,
    required this.card,
    required this.secretsVisible,
    required this.onToggleSecrets,
    required this.onCheckIn,
    required this.onExportIcs,
    required this.onEdit,
    required this.onDelete,
    required this.onFlip,
  });

  final SimCard card;
  final bool secretsVisible;
  final VoidCallback onToggleSecrets;
  final VoidCallback onCheckIn;
  final VoidCallback onExportIcs;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onFlip;

  String _mask(String v) => secretsVisible ? (v.isEmpty ? '—' : v) : '••••';

  @override
  Widget build(BuildContext context) {
    final last = card.lastKeepAliveDate;
    Widget kv(String k, String v) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
                width: 54,
                child: Text(k,
                    style: Hud.mono.copyWith(fontSize: 10, color: Hud.dim))),
            Expanded(
                child: Text(v,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Hud.mono.copyWith(
                        fontSize: 11.5, fontWeight: FontWeight.w600))),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(right: chamferSize - 6),
        child: Row(children: [
          const HudLabel('Security Vault · 卡背'),
          const Spacer(),
          _smallButton(secretsVisible ? '隐藏机密' : '解密查看', onToggleSecrets,
              key: Key('secrets-${card.id}')),
        ]),
      ),
      const SizedBox(height: 10),
      kv('ICCID', card.iccid.isEmpty ? '未录入' : card.iccid),
      kv('PIN/PUK', '${_mask(card.pin1)} / ${_mask(card.puk1)}'),
      if (card.esimLpaCode.isNotEmpty) kv('LPA', _mask(card.esimLpaCode)),
      const SizedBox(height: 4),
      const HudLabel('保号规则', color: Hud.amber),
      const SizedBox(height: 4),
      kv('周期',
          '每 ${card.keepAliveCycleDays} 天 · ${card.keepAliveAction.isEmpty ? '未设置动作' : card.keepAliveAction}'),
      kv(
          '上次',
          last == null
              ? '尚未打卡'
              : '${DateFormat('yyyy-MM-dd').format(last)} · 共 ${card.keepAliveLog.length} 次记录'),
      const Spacer(),
      Wrap(spacing: 6, runSpacing: Hud.isCompact(context) ? 0 : 6, children: [
        _smallButton('保号打卡', onCheckIn,
            key: Key('back-checkin-${card.id}'), color: Hud.emerald),
        _smallButton('导出 .ics', onExportIcs,
            key: Key('ics-${card.id}'), color: Hud.sky),
        _smallButton('编辑', onEdit, key: Key('edit-${card.id}')),
        _smallButton('删除', onDelete,
            key: Key('delete-${card.id}'), color: Hud.rose),
        _smallButton('返回正面 ↺', onFlip, key: Key('unflip-${card.id}')),
      ]),
    ]);
  }
}
