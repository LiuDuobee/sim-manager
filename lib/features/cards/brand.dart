import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/sim_card.dart';
import '../hud/hud_theme.dart';
import '../hud/motion.dart';

/// Quiet brand hue per carrier, matched by preset id or carrier name. Used
/// for the card face tint, the countdown ring track and the globe node.
Color? _brandHue(SimCard c) {
  final key = '${c.carrierPresetId} ${c.carrierName}'.toLowerCase();
  for (final (needle, color) in const [
    ('t-mobile', Color(0xFFE20074)),
    ('tmobile', Color(0xFFE20074)),
    ('cmcc', Color(0xFF0085D0)),
    ('中国移动', Color(0xFF0085D0)),
    ('giffgaff', Color(0xFF7C3AED)),
    ('club', Color(0xFF00A99D)),
    ('csl', Color(0xFF00A99D)),
    ('rakuten', Color(0xFFBF0000)),
    ('乐天', Color(0xFFBF0000)),
    ('povo', Color(0xFFE5C100)),
    ('vodafone', Color(0xFFE60000)),
    ('ais', Color(0xFF7CB342)),
  ]) {
    if (key.contains(needle)) return color;
  }
  return null;
}

/// Brand colour calibrated for the current palette: lifted on dark, deepened
/// on light, and always desaturated so it stays quiet next to HUD accents.
Color brandColor(SimCard c, HudPalette p) {
  final hue = _brandHue(c);
  final base = hue ??
      HSLColor.fromAHSL(
              1, (c.countryCode.hashCode % 360).abs().toDouble(), .5, .5)
          .toColor();
  final hsl = HSLColor.fromColor(base);
  return hsl
      .withSaturation(math.min(hsl.saturation, .62))
      .withLightness(p.isDark ? .62 : .40)
      .toColor();
}

/// Card face gradient: the carrier's brand hue fading into the card's dark
/// body. Cards without a known brand keep their country gradient.
List<Color>? brandGradient(SimCard c) {
  final hue = _brandHue(c);
  if (hue == null) return null;
  final hsl = HSLColor.fromColor(hue);
  return [
    hsl
        .withSaturation(math.min(hsl.saturation, .7))
        .withLightness(.30)
        .toColor(),
    hsl
        .withSaturation(math.min(hsl.saturation, .6))
        .withLightness(.16)
        .toColor(),
    const Color(0xFF0F172A),
  ];
}

/// Remaining-days countdown ring: the arc is the share of the keep-alive
/// cycle still left, coloured by urgency on a brand-tinted track. The tier
/// code is printed under the number so state never relies on colour alone.
class CountdownRing extends StatelessWidget {
  const CountdownRing({
    super.key,
    required this.card,
    this.size = 46,
    this.palette,
    this.showTier = true,
  });

  final SimCard card;
  final double size;
  final HudPalette? palette;
  final bool showTier;

  @override
  Widget build(BuildContext context) {
    final p = palette ?? context.hud;
    if (!card.hasDeadline) {
      return Semantics(
        label: '${card.carrierName} 无保号规则',
        child: SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: _RingPainter(
                progress: 0,
                color: p.muted,
                track: brandColor(card, p).withValues(alpha: .28),
                stroke: size * .1),
            child: Center(
                child: Text('—',
                    style: Hud.mono.copyWith(
                        fontSize: size * .3,
                        fontWeight: FontWeight.w900,
                        color: p.muted))),
          ),
        ),
      );
    }
    final days = card.daysRemaining();
    final tier = urgencyTierFor(days);
    final span = card.tracksPlanExpiry
        ? (card.planDays ?? card.keepAliveCycleDays)
        : card.keepAliveCycleDays;
    final progress = (days / math.max(span, 1)).clamp(0.0, 1.0).toDouble();
    final color = p.tierColor(tier);
    return Semantics(
      label: '${card.carrierName} 剩余 $days 天，${tier.label}',
      child: SizedBox.square(
        dimension: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: progress),
          duration: Motion.of(context, Motion.long),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => CustomPaint(
            painter: _RingPainter(
                progress: v,
                color: color,
                track: brandColor(card, p).withValues(alpha: .28),
                stroke: size * .1),
            child: Center(
              child: FittedBox(
                child: Padding(
                  padding: EdgeInsets.all(size * .16),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(days < 0 ? '!' : '$days',
                        style: Hud.mono.copyWith(
                            fontSize: 16,
                            height: 1,
                            fontWeight: FontWeight.w900,
                            color: color)),
                    if (showTier)
                      Text(tier.code,
                          style: Hud.mono.copyWith(
                              fontSize: 8, height: 1.2, color: p.muted)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(
      {required this.progress,
      required this.color,
      required this.track,
      required this.stroke});

  final double progress, stroke;
  final Color color, track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawArc(
        rect,
        0,
        math.pi * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = track);
    canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter o) =>
      o.progress != progress || o.color != color || o.track != track;
}
