import 'package:flutter/material.dart';

import '../../services/region_catalog.dart';
import '../hud/hud_theme.dart';

/// Flag of an ISO-2 region drawn from the bundled Twemoji flag font, so it
/// renders on Windows too (Segoe UI Emoji has no flag glyphs).
class FlagText extends StatelessWidget {
  const FlagText(this.code, {super.key, this.size = 16});

  final String code;
  final double size;

  @override
  Widget build(BuildContext context) => Text(flagEmoji(code),
      semanticsLabel: regionName(code),
      style: TextStyle(
          fontFamily: 'TwemojiCountryFlags',
          fontFamilyFallback: const ['Noto Color Emoji', 'Apple Color Emoji'],
          fontSize: size,
          height: 1.1));
}

/// The region's flag colour, lightness-calibrated so the accent stripe keeps
/// at least 3:1 against [background] (WCAG 1.4.11 for UI graphics).
Color regionAccent(String code, Color background) {
  final hsl = HSLColor.fromColor(regionFor(code).flagColor);
  final dark = background.computeLuminance() < .5;
  var c = hsl.withSaturation(hsl.saturation.clamp(.45, .85));
  for (var i = 0; i < 20; i++) {
    final color = c.toColor();
    if (contrastRatio(color, background) >= 3) return color;
    c = c.withLightness(
        (c.lightness + (dark ? .03 : -.03)).clamp(0.0, 1.0).toDouble());
  }
  return c.toColor();
}

double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + .05) / (lo + .05);
}

/// Thin flag-colour band for card faces and list rows (never a full tint).
class RegionStripe extends StatelessWidget {
  const RegionStripe(
      {super.key, required this.code, required this.background, this.width});

  final String code;
  final Color background;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final c = regionAccent(code, background);
    return Container(
      key: Key('region-stripe-$code'),
      width: width,
      height: 3,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        gradient: LinearGradient(colors: [c, c.withValues(alpha: 0)]),
      ),
    );
  }
}

/// Small text badge used for plan type / card kind on faces and rows.
class KindBadge extends StatelessWidget {
  const KindBadge(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.hud.sky;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: .6)),
        color: c.withValues(alpha: .12),
      ),
      child: Text(text,
          style: Hud.mono
              .copyWith(fontSize: 10, fontWeight: FontWeight.w800, color: c)),
    );
  }
}
