import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../models/sim_card.dart';

class Hud {
  static const mono = TextStyle(fontFamily: 'monospace', letterSpacing: .4);

  /// Below this logical width the app uses the phone layout.
  static const compactWidth = 600.0;

  /// Minimum touch target (Material / Android accessibility guideline).
  static const minTap = 48.0;

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < compactWidth;
}

/// Transparent edge-to-edge system bars with icons that contrast [b].
SystemUiOverlayStyle hudSystemUi(Brightness b) {
  final icons = b == Brightness.dark ? Brightness.light : Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: icons,
    statusBarBrightness: b,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: icons,
    systemNavigationBarContrastEnforced: false,
  );
}

ThemeData buildHudTheme(HudPalette p) => ThemeData(
      brightness: p.brightness,
      useMaterial3: true,
      scaffoldBackgroundColor: p.bg,
      colorScheme: ColorScheme.fromSeed(
          seedColor: p.sky, brightness: p.brightness, surface: p.panel),
      appBarTheme: AppBarTheme(
        systemOverlayStyle: hudSystemUi(p.brightness),
        backgroundColor: p.bg,
        foregroundColor: p.fg,
        surfaceTintColor: Colors.transparent,
      ),
      extensions: [p],
      fontFamilyFallback: const [
        'Microsoft YaHei',
        'PingFang SC',
        'Noto Sans CJK SC',
        'Noto Sans SC',
      ],
    );

extension HudContext on BuildContext {
  /// The HUD palette of the current theme (dark or light).
  HudPalette get hud =>
      Theme.of(this).extension<HudPalette>() ?? HudPalette.dark;
}

/// Every colour the HUD paints with, in a dark and a light set.
///
/// Dark is the original cockpit. Light follows the daylight tokens of
/// Solid Glass (deeplethe/solid-glass, `src/solid-glass.css` `:root`):
/// a cool grey page, smoked-white panes, a white rim on the top edge, a cool
/// hairline and a contact + lift shadow. Accents are the same hues taken a
/// few steps darker so text stays above WCAG AA (4.5:1) on the panes.
@immutable
class HudPalette extends ThemeExtension<HudPalette> {
  const HudPalette({
    required this.brightness,
    required this.bg,
    required this.panel,
    required this.fg,
    required this.line,
    required this.sky,
    required this.rose,
    required this.amber,
    required this.emerald,
    required this.violet,
    required this.blue,
    required this.muted,
    required this.dim,
    required this.onAccent,
    required this.glassTint,
    required this.glassBorder,
    required this.glassRim,
    required this.glassEdge,
    required this.glassShadow,
    required this.well,
    required this.wellEdge,
    required this.control,
    required this.dockTint,
    required this.floatTint,
    required this.glassSheen,
    required this.stageGradient,
    required this.stageFade,
    required this.tileGradient,
    required this.ocean,
    required this.halo,
    required this.grid,
    required this.land,
    required this.landActive,
    required this.landSelected,
    required this.landBorder,
    required this.nightShade,
    required this.globeRim,
    required this.nodeRing,
    required this.nodeLabelBg,
    required this.nodeLabelFg,
  });

  final Brightness brightness;
  final Color bg, panel, fg, line;
  final Color sky, rose, amber, emerald, violet, blue, muted, dim;

  /// Text on a filled accent (selected pill, selected slot).
  final Color onAccent;
  final Color glassTint, glassBorder, glassRim, glassEdge;
  final List<BoxShadow> glassShadow;

  /// Recessed cells inside a pane (telemetry cells, empty slots, pills).
  final Color well, wellEdge;
  final Color control, dockTint;

  /// Tint of floating glass (top bars, dock, sheets) over the blurred,
  /// saturated backdrop; opaque enough to keep text readable over any content.
  final Color floatTint;

  /// Top highlight of floating glass.
  final Color glassSheen;
  final List<Color> stageGradient, tileGradient;
  final Color stageFade;
  final List<Color> ocean;
  final Color halo, grid, land, landActive, landSelected, landBorder;
  final Color nightShade, globeRim, nodeRing, nodeLabelBg, nodeLabelFg;

  bool get isDark => brightness == Brightness.dark;

  Color tierColor(UrgencyTier t) => switch (t) {
        UrgencyTier.p1 => rose,
        UrgencyTier.p2 => amber,
        UrgencyTier.ok => emerald,
      };

  Color mediaColor(MediaType m) => switch (m) {
        MediaType.physical => blue,
        MediaType.esim => violet,
        MediaType.programmable => amber,
      };

  static const dark = HudPalette(
    brightness: Brightness.dark,
    bg: Color(0xFF030712),
    panel: Color(0xFF0B1222),
    fg: Colors.white,
    line: Color(0x1AFFFFFF),
    sky: Color(0xFF38BDF8),
    rose: Color(0xFFFB7185),
    amber: Color(0xFFFBBF24),
    emerald: Color(0xFF34D399),
    violet: Color(0xFFA78BFA),
    blue: Color(0xFF3B82F6),
    muted: Color(0xFF94A3B8),
    dim: Color(0xFF64748B),
    onAccent: Color(0xFF020617),
    glassTint: Color(0x8C020617),
    glassBorder: Color(0x3338BDF8),
    glassRim: Color(0x29FFFFFF),
    glassEdge: Color(0x14FFFFFF),
    glassShadow: [
      BoxShadow(color: Color(0x1A000000), offset: Offset(0, 1), blurRadius: 2),
      BoxShadow(
          color: Color(0x99000000),
          offset: Offset(0, 12),
          blurRadius: 32,
          spreadRadius: -14),
    ],
    well: Color(0x99020617),
    wellEdge: Color(0x0FFFFFFF),
    control: Color(0x8C0B1222),
    dockTint: Color(0xD90B1222),
    floatTint: Color(0xB80B1222),
    glassSheen: Color(0x1FFFFFFF),
    stageGradient: [Color(0xFF0A1528), Color(0xFF050B17), Color(0xFF02050C)],
    stageFade: Color(0xD902050C),
    tileGradient: [Color(0xFF0D1730), Color(0xFF070D1C)],
    ocean: [Color(0xFF12305A), Color(0xFF071530), Color(0xFF030814)],
    halo: Color(0x3838BDF8),
    grid: Color(0x2438BDF8),
    land: Color(0xFF1B3354),
    landActive: Color(0x8C0EA5E9),
    landSelected: Color(0xBFFBBF24),
    landBorder: Color(0x597DD3FC),
    nightShade: Color(0x8C000000),
    globeRim: Color(0x737DD3FC),
    nodeRing: Colors.white,
    nodeLabelBg: Color(0xD1020617),
    nodeLabelFg: Colors.white,
  );

  static const light = HudPalette(
    brightness: Brightness.light,
    // --background oklch(0.925 0.007 265)
    bg: Color(0xFFE4E6EB),
    // opaque --card oklch(0.958 0.005 265)
    panel: Color(0xFFEFF1F5),
    fg: Color(0xFF0F172A),
    // --border oklch(0.3 0.02 265 / 13%)
    line: Color(0x21292E38),
    sky: Color(0xFF0369A1),
    rose: Color(0xFFBE123C),
    amber: Color(0xFF92400E),
    emerald: Color(0xFF065F46),
    violet: Color(0xFF6D28D9),
    blue: Color(0xFF1D4ED8),
    muted: Color(0xFF475569),
    dim: Color(0xFF556274),
    onAccent: Colors.white,
    // --card oklch(0.98 0.004 265 / 60%)
    glassTint: Color(0x99F7F8FB),
    glassBorder: Color(0x400369A1),
    // --glass-rim oklch(1 0 0 / 90%), --glass-edge oklch(0.38 0.03 265 / 10%)
    glassRim: Color(0xE6FFFFFF),
    glassEdge: Color(0x1A3B4253),
    // --glass-contact / --glass-lift
    glassShadow: [
      BoxShadow(color: Color(0x0F1B2130), offset: Offset(0, 1), blurRadius: 2),
      BoxShadow(
          color: Color(0x241B2130),
          offset: Offset(0, 12),
          blurRadius: 32,
          spreadRadius: -14),
    ],
    // --field oklch(1 0 0 / 60%), --field-edge oklch(0.3 0.02 265 / 14%)
    well: Color(0x99FFFFFF),
    wellEdge: Color(0x24292E38),
    // --glass-control oklch(1 0 0 / 55%)
    control: Color(0x8CFFFFFF),
    // --popover oklch(0.985 0.003 265 / 96%) a step thinner
    dockTint: Color(0xD9F9FAFC),
    floatTint: Color(0xC7F9FAFC),
    glassSheen: Color(0x8CFFFFFF),
    stageGradient: [Color(0xFFF6F7FA), Color(0xFFEDF0F4), Color(0xFFE3E7ED)],
    stageFade: Color(0xD9E3E7ED),
    tileGradient: [Color(0xFFF9FAFC), Color(0xFFF0F2F6)],
    ocean: [Color(0xFFE3EFFA), Color(0xFFC8DDF1), Color(0xFFA9C4E2)],
    halo: Color(0x330284C7),
    grid: Color(0x290369A1),
    land: Color(0xFFF8FAFC),
    landActive: Color(0xA638BDF8),
    landSelected: Color(0xBFF59E0B),
    landBorder: Color(0x730369A1),
    nightShade: Color(0x381E3A5F),
    globeRim: Color(0x8C0369A1),
    nodeRing: Colors.white,
    nodeLabelBg: Color(0xF2FFFFFF),
    nodeLabelFg: Color(0xFF0F172A),
  );

  @override
  HudPalette copyWith() => this;

  @override
  HudPalette lerp(HudPalette? other, double t) =>
      other == null || t < .5 ? this : other;
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
    this.tint,
    this.borderColor,
    this.shadow = true,
    this.solid = false,
    this.floating = false,
    this.borderRadius,
  });

  /// Floating layers (top bar, dock, sheets) get the full frosted treatment:
  /// a wide blur of what scrolls underneath, a saturation lift and a top
  /// sheen. Inside a [BackdropGroup] they share one backdrop snapshot.
  final bool floating;
  final BorderRadius? borderRadius;

  static const floatingSigma = 22.0;
  static const floatingSaturation = 1.8;

  /// Content surfaces are solid (no blur, opaque face); glass is kept for
  /// navigation and floating layers. High-contrast mode makes every pane
  /// solid so text never sits on a see-through background.
  final bool solid;
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color? tint;
  final Color? borderColor;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final r = borderRadius ?? BorderRadius.circular(radius);
    final h = context.hud;
    if (solid || (MediaQuery.maybeHighContrastOf(context) ?? false)) {
      return CustomPaint(
        foregroundPainter: GlassRimPainter(radius: radius, color: h.glassRim),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: h.panel,
            borderRadius: r,
            border: Border.all(color: h.line),
            boxShadow: shadow ? h.glassShadow : null,
          ),
          child: child,
        ),
      );
    }
    if (floating) return _floating(context, r);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: shadow ? h.glassShadow : null,
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: CustomPaint(
            foregroundPainter:
                GlassRimPainter(radius: radius, color: h.glassRim),
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                color: tint ?? h.glassTint,
                borderRadius: r,
                border: Border.all(color: borderColor ?? h.glassBorder),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Widget _floating(BuildContext context, BorderRadius r) {
    final h = context.hud;
    final filter = ImageFilter.compose(
      outer: ImageFilter.blur(
          sigmaX: floatingSigma,
          sigmaY: floatingSigma,
          tileMode: TileMode.mirror),
      inner: ColorFilter.matrix(saturationMatrix(floatingSaturation)),
    );
    final face = CustomPaint(
      foregroundPainter:
          GlassRimPainter(radius: r.topLeft.x, color: h.glassRim),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tint ?? h.floatTint,
          borderRadius: r,
          border: Border.all(color: borderColor ?? h.glassBorder),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: r,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, .45],
              colors: [h.glassSheen, h.glassSheen.withValues(alpha: 0)],
            ),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    final grouped = BackdropGroup.of(context) != null;
    return DecoratedBox(
      key: const Key('floating-glass'),
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: shadow ? h.glassShadow : null,
      ),
      child: ClipRRect(
        borderRadius: r,
        child: grouped
            ? BackdropFilter.grouped(filter: filter, child: face)
            : BackdropFilter(filter: filter, child: face),
      ),
    );
  }
}

/// Colour matrix that scales saturation by [s] (1 = unchanged), Rec. 709.
List<double> saturationMatrix(double s) {
  const r = .2126, g = .7152, b = .0722;
  final i = 1 - s;
  return [
    r * i + s, g * i, b * i, 0, 0, //
    r * i, g * i + s, b * i, 0, 0, //
    r * i, g * i, b * i + s, 0, 0, //
    0, 0, 0, 1, 0,
  ];
}

/// Modal sheet on floating glass: the page behind stays visible, blurred.
Future<T?> showGlassBottomSheet<T>(BuildContext context,
        {required WidgetBuilder builder, bool isScrollControlled = false}) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: GlassPanel(
          key: const Key('glass-sheet'),
          floating: true,
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: ctx.hud.muted.withValues(alpha: .5),
                  borderRadius: BorderRadius.circular(2)),
            ),
            Flexible(
                child: Material(
                    type: MaterialType.transparency, child: builder(ctx))),
          ]),
        ),
      ),
    );

/// The top line of light of a Solid Glass pane, fading out toward the sides.
class GlassRimPainter extends CustomPainter {
  const GlassRimPainter({required this.radius, required this.color});

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
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final compact = Hud.isCompact(context);
    final h = context.hud;
    final color = this.color ?? h.sky;
    final pill = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 14 : 12, vertical: compact ? 9 : 6),
      decoration: BoxDecoration(
        color: selected ? color : h.well,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
            color: selected
                ? color
                : (h.isDark ? const Color(0x1FFFFFFF) : h.wellEdge)),
        boxShadow: selected
            ? [BoxShadow(color: color.withValues(alpha: .35), blurRadius: 12)]
            : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label,
            style: TextStyle(
                fontSize: compact ? 13 : 12,
                fontWeight: FontWeight.w700,
                color: selected ? h.onAccent : h.fg)),
        if (count != null) ...[
          const SizedBox(width: 6),
          Text('$count',
              style: Hud.mono.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected ? h.onAccent : h.muted)),
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
  const HudLabel(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Hud.mono.copyWith(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.6,
          color: color ?? context.hud.sky));
}

/// Reports its child's laid-out size after each layout that changes it.
class SizeReporter extends SingleChildRenderObjectWidget {
  const SizeReporter({super.key, required this.onSize, super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderSizeReporter(onSize);

  @override
  void updateRenderObject(
          BuildContext context, RenderSizeReporter renderObject) =>
      renderObject.onSize = onSize;
}

class RenderSizeReporter extends RenderProxyBox {
  RenderSizeReporter(this.onSize);

  ValueChanged<Size> onSize;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _last) return;
    _last = size;
    final s = size;
    WidgetsBinding.instance.addPostFrameCallback((_) => onSize(s));
  }
}
