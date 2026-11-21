import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:intl/intl.dart';

import '../../models/sim_card.dart';
import '../hud/hud_theme.dart';
import '../hud/motion.dart';
import 'brand.dart';
import 'region_flag.dart';
import 'show_number_page.dart';

const chamferSize = 28.0;

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
    this.onSmsRenewal,
    this.highlighted = false,
  });

  final SimCard card;
  final VoidCallback onCheckIn;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onExportIcs;

  /// Opens the paste-an-SMS renewal sheet; hidden when null.
  final VoidCallback? onSmsRenewal;
  final bool highlighted;

  @override
  State<FlipSimCard> createState() => FlipSimCardState();
}

class FlipSimCardState extends State<FlipSimCard>
    with TickerProviderStateMixin {
  /// 0 = front, 1 = back. Driven by a spring so a second tap mid-flip turns
  /// back from where the card is, keeping its velocity (settles ≈ 650 ms).
  late final AnimationController _flip =
      AnimationController.unbounded(vsync: this);
  late final AnimationController _stamp = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600));
  bool _secretsVisible = false;
  bool _flipped = false;

  bool get isFlipped => _flipped;

  void toggle() {
    _flipped = !_flipped;
    final to = _flipped ? 1.0 : 0.0;
    Haptics.tick();
    if (Motion.reduced(context)) {
      _flip.value = to;
      return;
    }
    _flip.animateWith(
        SpringSimulation(Motion.flipSpring, _flip.value, to, _flip.velocity));
  }

  @override
  void didUpdateWidget(FlipSimCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final events = widget.card.events;
    final checkedIn = widget.card.id == oldWidget.card.id &&
        events.length > oldWidget.card.events.length &&
        (events.first.type == CardEventType.checkIn ||
            events.first.type == CardEventType.topUp);
    if (checkedIn) {
      Haptics.success();
      if (Motion.reduced(context)) {
        _stamp.value = .5;
        _stamp.animateTo(1, duration: const Duration(milliseconds: 1200));
      } else {
        _stamp.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _flip.dispose();
    _stamp.dispose();
    super.dispose();
  }

  // A SIM card is a physical, dark object of fixed size: it keeps its dark
  // face and palette in both app themes, and its print grows with the
  // system text size only up to 1.15× (the passport page shows everything
  // at full scale).
  @override
  Widget build(BuildContext context) => MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: Theme(
        data: buildHudTheme(HudPalette.dark),
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: Colors.white),
          child: IconTheme.merge(
            data: const IconThemeData(color: Colors.white),
            child: Builder(builder: _build),
          ),
        ),
      ));

  Widget _build(BuildContext context) {
    final card = widget.card;
    final border = widget.highlighted
        ? context.hud.amber
        : Colors.white.withValues(alpha: .14);
    return GestureDetector(
      onTap: toggle,
      child: AnimatedBuilder(
        animation: _flip,
        builder: (context, _) {
          final angle = _flip.value * math.pi;
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
                    onSmsRenewal: widget.onSmsRenewal,
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
                          ? brandGradient(card) ??
                              cardGradient(card.countryCode)
                          : const [Color(0xFF0F172A), Color(0xFF020617)],
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Stack(fit: StackFit.expand, children: [
                    face,
                    if (showFront)
                      _Stamp(animation: _stamp, key: Key('stamp-${card.id}')),
                  ]),
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
    final color = context.hud.tierColor(tier);
    final span = card.tracksPlanExpiry
        ? (card.planDays ?? card.keepAliveCycleDays)
        : card.keepAliveCycleDays;
    final progress = card.hasDeadline
        ? (days / math.max(span, 1)).clamp(0.0, 1.0).toDouble()
        : 0.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(right: chamferSize - 6),
        child: LayoutBuilder(
            builder: (context, box) => Row(children: [
                  FlagText(card.countryCode,
                      key: Key('flag-${card.id}'), size: 15),
                  const SizedBox(width: 4),
                  Text(card.countryCode,
                      style: Hud.mono.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: context.hud.muted)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(card.carrierName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800)),
                  ),
                  _FitAtMost(
                    maxWidth: box.maxWidth * .62,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        _Tag(card.mediaType.label,
                            color: context.hud.mediaColor(card.mediaType)),
                        const SizedBox(width: 6),
                        _Tag(card.isActive ? 'ONLINE' : 'STORED',
                            color: card.isActive
                                ? context.hud.emerald
                                : context.hud.sky),
                      ]),
                    ),
                  ),
                ])),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: RegionStripe(
            code: card.countryCode,
            background: const Color(0xFF0F172A),
            width: 96),
      ),
      Row(children: [
        Flexible(
          child: Text(card.planName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: context.hud.muted)),
        ),
        if (card.planType == PlanType.postpaid) ...[
          const SizedBox(width: 6),
          KindBadge(PlanType.postpaid.label,
              key: Key('postpaid-${card.id}'), color: context.hud.amber),
        ],
        if (card.kind != CardKind.voice) ...[
          const SizedBox(width: 6),
          KindBadge(card.kindLabel, key: Key('kind-${card.id}')),
        ],
      ]),
      const SizedBox(height: 8),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _SimChip(),
        const SizedBox(width: 10),
        Hero(
            tag: 'ring-${card.id}',
            child: CountdownRing(
                key: Key('ring-${card.id}'),
                card: card,
                size: Hud.isCompact(context) ? 50 : 44)),
        const SizedBox(width: 10),
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
                  style: Hud.mono
                      .copyWith(fontSize: 10.5, color: context.hud.muted)),
            ]),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 6, runSpacing: 4, children: [
        _Tag('${card.hostName} · ${card.slotDetail}'),
        if (card.estkSlotNumber != null)
          _Tag(
              'eSTK #${card.estkSlotNumber}'
              '${card.profileName.isEmpty ? '' : ' · ${card.profileName}'}',
              color: context.hud.amber),
        for (final t in card.tags) _Tag('#$t', color: context.hud.emerald),
      ]),
      const Spacer(),
      Row(children: [
        Expanded(
          child: Text(
              card.hasDeadline
                  ? '${card.tracksPlanExpiry ? '套餐到期' : '到期'} ${DateFormat('yyyy-MM-dd').format(card.effectiveDeadline)}'
                  : card.planType == PlanType.postpaid
                      ? '上台合约 · 无保号规则'
                      : '无保号规则',
              style: Hud.mono.copyWith(fontSize: 11, color: context.hud.muted)),
        ),
        Text(
            card.hasDeadline
                ? '${tier.code} · ${days < 0 ? '已过期 ${-days}' : '剩 $days'} 天'
                : '—',
            key: Key('days-${card.id}'),
            style: Hud.mono.copyWith(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: card.hasDeadline ? color : context.hud.muted)),
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
            key: Key('checkin-${card.id}'), color: context.hud.emerald),
        const SizedBox(width: 6),
        _smallButton(
            '出示',
            () => Navigator.of(context).push(MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) => ShowNumberPage(card: card))),
            key: Key('show-${card.id}'),
            color: context.hud.sky),
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
    this.onSmsRenewal,
  });

  final SimCard card;
  final bool secretsVisible;
  final VoidCallback onToggleSecrets;
  final VoidCallback onCheckIn;
  final VoidCallback onExportIcs;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onFlip;
  final VoidCallback? onSmsRenewal;

  String _mask(String v) => secretsVisible ? (v.isEmpty ? '—' : v) : '••••';

  @override
  Widget build(BuildContext context) {
    final last = card.lastKeepAliveDate;
    Widget kv(String k, String v, {int maxLines = 2}) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
                width: 54,
                child: Text(k,
                    style: Hud.mono
                        .copyWith(fontSize: 10, color: context.hud.dim))),
            Expanded(
                child: Text(v,
                    maxLines: maxLines,
                    overflow: TextOverflow.ellipsis,
                    style: Hud.mono.copyWith(
                        fontSize: 11.5, fontWeight: FontWeight.w600))),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(right: chamferSize - 6),
        child: LayoutBuilder(
            builder: (context, box) => Row(children: [
                  Hero(
                      tag: 'ring-${card.id}',
                      child:
                          CountdownRing(card: card, size: 28, showTier: false)),
                  const SizedBox(width: 8),
                  const Expanded(child: HudLabel('Security Vault · 卡背')),
                  // Large text: the chips shrink to fit instead of overflowing.
                  _FitAtMost(
                    maxWidth: box.maxWidth * .62,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        _smallButton('护照 ${card.events.length}',
                            () => showPassport(context, card),
                            key: Key('passport-${card.id}'),
                            color: context.hud.amber),
                        const SizedBox(width: 6),
                        _smallButton(
                            secretsVisible ? '隐藏机密' : '解密查看', onToggleSecrets,
                            key: Key('secrets-${card.id}')),
                      ]),
                    ),
                  ),
                ])),
      ),
      const SizedBox(height: 10),
      // Scrolls only when large system text makes the details taller than
      // the card.
      Expanded(
          child: SingleChildScrollView(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
            kv('ICCID', card.iccid.isEmpty ? '未录入' : card.iccid),
            kv('PIN/PUK', '${_mask(card.pin1)} / ${_mask(card.puk1)}'),
            if (card.esimLpaCode.isNotEmpty) kv('LPA', _mask(card.esimLpaCode)),
            const SizedBox(height: 4),
            HudLabel('保号规则 · 续费护照', color: context.hud.amber),
            const SizedBox(height: 4),
            kv('规则',
                '${card.keepAliveType.label} · ${card.renewalBasis.label} · 每 ${card.keepAliveCycleDays} 天 · 年 ${card.currency} ${card.annualCost.toStringAsFixed(card.annualCost % 1 == 0 ? 0 : 2)}',
                maxLines: 1),
            kv('动作',
                card.keepAliveAction.isEmpty ? '未设置动作' : card.keepAliveAction,
                maxLines: 1),
            kv(
                '护照',
                card.events.isEmpty
                    ? (last == null
                        ? '尚未打卡'
                        : '上次 ${DateFormat('yyyy-MM-dd').format(last)}')
                    : '${passportLine(card.events.first)} · 共 ${card.events.length} 条',
                maxLines: 1),
          ]))),
      Wrap(spacing: 6, runSpacing: Hud.isCompact(context) ? 0 : 6, children: [
        _smallButton('保号打卡', onCheckIn,
            key: Key('back-checkin-${card.id}'), color: context.hud.emerald),
        _smallButton('导出 .ics', onExportIcs,
            key: Key('ics-${card.id}'), color: context.hud.sky),
        if (onSmsRenewal != null)
          _smallButton('短信录入', onSmsRenewal!,
              key: Key('sms-${card.id}'), color: context.hud.amber),
        _smallButton('编辑', onEdit, key: Key('edit-${card.id}')),
        _smallButton('归档', onDelete,
            key: Key('delete-${card.id}'), color: context.hud.rose),
        _smallButton('返回正面 ↺', onFlip, key: Key('unflip-${card.id}')),
      ]),
    ]);
  }
}

String _amount(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 2);

/// One-line passport entry: `12-03 充值续期 USD 3 → 2027-01-02`.
String passportLine(CardEvent e) => [
      DateFormat('MM-dd').format(e.at),
      e.type.label,
      if (e.amount != null) '${e.currency} ${_amount(e.amount!)}',
      if (e.deadline != null)
        '→ ${DateFormat('yyyy-MM-dd').format(e.deadline!)}',
      if (e.note.isNotEmpty) e.note,
    ].join(' ');

/// The full renewal passport of [card] as its own page: the countdown ring
/// flies in from the card (Hero), then rules, cost and the timeline fade up.
Future<void> showPassport(BuildContext context, SimCard card) =>
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => PassportPage(card: card)));

class PassportPage extends StatelessWidget {
  const PassportPage({super.key, required this.card});

  final SimCard card;

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    Widget rise(int i, Widget child) => TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Motion.of(context, Motion.long),
          curve: Interval((.12 * i).clamp(0, .6).toDouble(), 1,
              curve: Curves.easeOutCubic),
          builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.translate(
                  offset: Offset(0, 12 * (1 - t)), child: child)),
          child: child,
        );
    return Scaffold(
      key: const Key('passport-dialog'),
      appBar: AppBar(title: Text('续费护照 · ${card.carrierName}')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Row(children: [
          Hero(
              tag: 'ring-${card.id}',
              child: CountdownRing(card: card, size: 96)),
          const SizedBox(width: 18),
          Expanded(
            child: rise(
                0,
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                      '${card.keepAliveType.label} · ${card.renewalBasis.label} · 每 ${card.keepAliveCycleDays} 天',
                      style: TextStyle(
                          color: h.amber, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                      '预估年成本 ${card.currency} ${_amount(card.annualCost)} ≈ ¥${card.annualCny.toStringAsFixed(0)}',
                      key: const Key('passport-annual'),
                      style: Hud.mono.copyWith(fontSize: 12, color: h.emerald)),
                  if (card.rechargeUrl.isNotEmpty)
                    SelectableText('充值 ${card.rechargeUrl}',
                        style: Hud.mono.copyWith(fontSize: 11, color: h.sky)),
                ])),
          ),
        ]),
        const SizedBox(height: 20),
        HudLabel('时间线 · ${card.events.length} 条', color: h.muted),
        const SizedBox(height: 10),
        if (card.events.isEmpty)
          Text('暂无记录', style: TextStyle(color: h.dim))
        else
          for (final (i, e) in card.events.indexed)
            rise(
                i + 1,
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 5, right: 10),
                          child:
                              Icon(_eventIcon(e.type), size: 14, color: h.sky),
                        ),
                        Expanded(
                            child: Text(passportLine(e),
                                style: Hud.mono.copyWith(fontSize: 12.5))),
                      ]),
                )),
      ]),
    );
  }
}

IconData _eventIcon(CardEventType t) => switch (t) {
      CardEventType.create => Icons.add_circle_outline,
      CardEventType.checkIn => Icons.check_circle_outline,
      CardEventType.topUp => Icons.payments_outlined,
      CardEventType.edit => Icons.edit_outlined,
      CardEventType.archive => Icons.inventory_2_outlined,
      CardEventType.restore => Icons.unarchive_outlined,
    };

/// 「已保号」 stamp dropped on the card face after a check-in: lands with a
/// spring overshoot, a ripple spreads, then it fades.
class _Stamp extends StatelessWidget {
  const _Stamp({super.key, required this.animation});

  final Animation<double> animation;

  static const _land = SpringCurve(Motion.snapSpring, .5);

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            final t = animation.value;
            if (t == 0 || t == 1) return const SizedBox.shrink();
            final land = _land.transform((t / .3).clamp(0.0, 1.0));
            final fade = t < .75 ? 1.0 : 1 - (t - .75) / .25;
            final ripple = (t / .5).clamp(0.0, 1.0);
            const color = Color(0xFF34D399);
            return Opacity(
              opacity: fade,
              child: Center(
                child: Stack(alignment: Alignment.center, children: [
                  Container(
                    width: 80 + 120 * ripple,
                    height: 80 + 120 * ripple,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: color.withValues(alpha: .5 * (1 - ripple)),
                          width: 2),
                    ),
                  ),
                  Transform.rotate(
                    angle: -.2,
                    child: Transform.scale(
                      scale: 1.8 - .8 * land,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xCC052E1C),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: color, width: 2.4),
                        ),
                        child: const Text('已保号',
                            style: TextStyle(
                                color: color,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 4)),
                      ),
                    ),
                  ),
                ]),
              ),
            );
          },
        ),
      );
}

/// Lets a row of chips take at most 62% of the row and scale down (large
/// system text) instead of overflowing it.
class _FitAtMost extends StatelessWidget {
  const _FitAtMost({required this.maxWidth, required this.child});

  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth), child: child);
}
