import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../models/sim_card.dart';

class Hud {
  static const bg = Color(0xFF030712);
  static const panel = Color(0xFF0B1222);
  static const line = Color(0x1AFFFFFF);
  static const sky = Color(0xFF38BDF8);
  static const rose = Color(0xFFFB7185);
  static const amber = Color(0xFFFBBF24);
  static const emerald = Color(0xFF34D399);
  static const violet = Color(0xFFA78BFA);
  static const blue = Color(0xFF3B82F6);
  static const muted = Color(0xFF94A3B8);
  static const dim = Color(0xFF64748B);

  static const mono = TextStyle(fontFamily: 'monospace', letterSpacing: .4);

  /// Below this logical width the app uses the phone layout.
  static const compactWidth = 600.0;

  /// Minimum touch target (Material / Android accessibility guideline).
  static const minTap = 48.0;

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < compactWidth;

  /// Solid Glass edge light and shadow.
  static const glassRim = Color(0x29FFFFFF);
  static const glassEdge = Color(0x14FFFFFF);
  static const glassShadow = [
    BoxShadow(color: Color(0x1A000000), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(
        color: Color(0x99000000),
        offset: Offset(0, 12),
        blurRadius: 32,
        spreadRadius: -14),
  ];

  static Color tierColor(UrgencyTier t) => switch (t) {
        UrgencyTier.p1 => rose,
        UrgencyTier.p2 => amber,
        UrgencyTier.ok => emerald,
      };

  static Color mediaColor(MediaType m) => switch (m) {
        MediaType.physical => blue,
        MediaType.esim => violet,
        MediaType.programmable => amber,
      };
}

/// Translucent, blurred HUD panel (telemetry readouts etc.).
///
/// Solid Glass finish: the face is one flat smoky tint; the material shows
/// only at the edge — a line of light along the top, a hairline all round and
/// a soft shadow gathered underneath.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.radius = 14,
    this.tint = const Color(0x8C020617),
    this.borderColor = const Color(0x3338BDF8),
    this.shadow = true,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color tint;
  final Color borderColor;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: shadow ? Hud.glassShadow : null,
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: CustomPaint(
            foregroundPainter: GlassRimPainter(radius: radius),
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                color: tint,
                borderRadius: r,
                border: Border.all(color: borderColor),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// The top line of light of a Solid Glass pane, fading out toward the sides.
class GlassRimPainter extends CustomPainter {
  const GlassRimPainter({required this.radius, this.color = Hud.glassRim});

  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = (Offset.zero & size).deflate(.75);
    final rrect = RRect.fromRectAndRadius(
        rect, Radius.circular(math.max(0, radius - .75)));
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(
        0, 0, size.width, math.min(size.height / 2, math.max(radius, 6))));
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(colors: [
          color.withValues(alpha: 0),
          color,
          color,
          color.withValues(alpha: 0),
        ], stops: const [
          0,
          .18,
          .82,
          1
        ]).createShader(Offset.zero & size),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(GlassRimPainter old) =>
      old.radius != radius || old.color != color;
}

/// Ensures a tap area of at least [Hud.minTap] around a smaller visual.
class TapTarget extends StatelessWidget {
  const TapTarget({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) => enabled
      ? ConstrainedBox(
          constraints:
              const BoxConstraints(minWidth: Hud.minTap, minHeight: Hud.minTap),
          child: Center(widthFactor: 1, heightFactor: 1, child: child),
        )
      : child;
}

class HudPill extends StatelessWidget {
  const HudPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.color = Hud.sky,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final compact = Hud.isCompact(context);
    final pill = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 14 : 12, vertical: compact ? 9 : 6),
      decoration: BoxDecoration(
        color: selected ? color : const Color(0x66020617),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
            color: selected ? color : Colors.white.withValues(alpha: .12)),
        boxShadow: selected
            ? [BoxShadow(color: color.withValues(alpha: .35), blurRadius: 12)]
            : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label,
            style: TextStyle(
                fontSize: compact ? 13 : 12,
                fontWeight: FontWeight.w700,
                color: selected ? const Color(0xFF020617) : Colors.white)),
        if (count != null) ...[
          const SizedBox(width: 6),
          Text('$count',
              style: Hud.mono.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected ? const Color(0xFF020617) : Hud.muted)),
        ],
      ]),
    );
    return InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: TapTarget(enabled: compact, child: pill),
    );
  }
}

class HudLabel extends StatelessWidget {
  const HudLabel(this.text, {super.key, this.color = Hud.sky});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Hud.mono.copyWith(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.6,
          color: color));
}
