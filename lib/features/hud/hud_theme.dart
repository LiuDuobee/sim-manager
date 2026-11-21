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
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.radius = 14,
    this.tint = const Color(0x8C020617),
    this.borderColor = const Color(0x3338BDF8),
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color tint;
  final Color borderColor;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: borderColor),
            ),
            child: child,
          ),
        ),
      );
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
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? color : const Color(0x66020617),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: selected ? color : Colors.white.withValues(alpha: .12)),
            boxShadow: selected
                ? [
                    BoxShadow(
                        color: color.withValues(alpha: .35), blurRadius: 12)
                  ]
                : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12,
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
        ),
      );
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
