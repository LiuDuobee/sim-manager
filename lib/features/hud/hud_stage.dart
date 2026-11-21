import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/sim_card.dart';
import '../globe/atlas_globe.dart';
import '../globe/country_meta.dart';
import '../globe/globe_controller.dart';
import '../globe/topojson.dart';
import 'hud_theme.dart';

/// Builds one globe node per country that has (filtered) cards. Positions come
/// from [countryFocus] or the country's polygon centroid in the atlas.
List<GlobeNode> buildGlobeNodes(List<SimCard> cards, List<GeoCountry> countries,
    {HudPalette palette = HudPalette.dark}) {
  final byCode = <String, List<SimCard>>{};
  for (final c in cards) {
    byCode.putIfAbsent(c.countryCode, () => []).add(c);
  }
  final nodes = <GlobeNode>[];
  byCode.forEach((code, group) {
    final pos = focusFor(code, countries);
    if (pos == null) return;
    final worst = group
        .map((c) => c.urgency())
        .reduce((a, b) => a.index < b.index ? a : b);
    nodes.add(GlobeNode(
      code: code,
      lon: pos.$1,
      lat: pos.$2,
      count: group.length,
      color: palette.tierColor(worst),
    ));
  });
  return nodes;
}

(double, double)? focusFor(String code, List<GeoCountry> countries) {
  final known = countryFocus[code];
  if (known != null) return known;
  for (final c in countries) {
    if (c.iso2 == code) return c.centroid;
  }
  return null;
}

String formatLon(double lon) =>
    '${lon.abs().toStringAsFixed(1)}°${lon >= 0 ? 'E' : 'W'}';
String formatLat(double lat) =>
    '${lat.abs().toStringAsFixed(1)}°${lat >= 0 ? 'N' : 'S'}';

/// Cockpit-style half-capsule stage: HUD strip on top, globe in the canopy,
/// translucent telemetry and controls floating over it, radar on the side.
class HudStage extends StatelessWidget {
  const HudStage({
    super.key,
    required this.allCards,
    required this.filteredCards,
    required this.countries,
    required this.atlasError,
    required this.controller,
    required this.mediaFilter,
    required this.onMediaFilter,
    required this.selectedCountry,
    required this.onSelectCountry,
    required this.onGlobeCountryTap,
    required this.onCheckIn,
  });

  final List<SimCard> allCards;
  final List<SimCard> filteredCards;
  final List<GeoCountry>? countries;
  final String? atlasError;
  final GlobeController controller;
  final MediaType? mediaFilter;
  final ValueChanged<MediaType?> onMediaFilter;
  final String? selectedCountry;
  final ValueChanged<String?> onSelectCountry;
  final void Function(String? iso2, String name, double lon, double lat)
      onGlobeCountryTap;
  final ValueChanged<SimCard> onCheckIn;

  @override
  Widget build(BuildContext context) {
    final mediaCards = mediaFilter == null
        ? allCards
        : allCards.where((c) => c.mediaType == mediaFilter).toList();
    final codes = <String>{for (final c in mediaCards) c.countryCode}.toList()
      ..sort();
    final nodes = buildGlobeNodes(filteredCards, countries ?? const [],
        palette: context.hud);

    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < Hud.compactWidth) {
        return _compactStage(
            context, constraints.maxWidth, mediaCards, codes, nodes);
      }
      final wide = constraints.maxWidth >= 980;
      return CustomPaint(
        painter: _CockpitFramePainter(context.hud),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
          child: Column(children: [
            _HudStrip(
              allCards: allCards,
              mediaCards: mediaCards,
              codes: codes,
              mediaFilter: mediaFilter,
              onMediaFilter: onMediaFilter,
              selectedCountry: selectedCountry,
              onSelectCountry: onSelectCountry,
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: wide ? 500 : 460,
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _globeArea(context, nodes)),
                    if (wide) ...[
                      const SizedBox(width: 14),
                      SizedBox(
                        width: 340,
                        child: _RadarDrawer(
                            cards: filteredCards, onCheckIn: onCheckIn),
                      ),
                    ],
                  ]),
            ),
            if (!wide) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 320,
                child: _RadarDrawer(cards: filteredCards, onCheckIn: onCheckIn),
              ),
            ],
          ]),
        ),
      );
    });
  }

  /// Phone portrait: the same cockpit, re-stacked. HUD strip rows scroll
  /// sideways, the globe gets a near-square canopy, telemetry moves out of
  /// the canopy into a 2×2 readout grid and the radar follows as a list.
  Widget _compactStage(BuildContext context, double width,
      List<SimCard> mediaCards, List<String> codes, List<GlobeNode> nodes) {
    final globeHeight = (width - 20).clamp(300.0, 440.0);
    return CustomPaint(
      key: const Key('hud-compact'),
      painter: _CockpitFramePainter(context.hud),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
        child: Column(children: [
          _HudStrip(
            compact: true,
            allCards: allCards,
            mediaCards: mediaCards,
            codes: codes,
            mediaFilter: mediaFilter,
            onMediaFilter: onMediaFilter,
            selectedCountry: selectedCountry,
            onSelectCountry: onSelectCountry,
          ),
          const SizedBox(height: 8),
          SizedBox(
              height: globeHeight,
              child: _globeArea(context, nodes, compact: true)),
          const SizedBox(height: 10),
          _Telemetry(
              compact: true,
              controller: controller,
              nodes: nodes,
              cards: filteredCards),
          const SizedBox(height: 10),
          _RadarDrawer(
              cards: filteredCards, onCheckIn: onCheckIn, compact: true),
        ]),
      ),
    );
  }

  /// The globe stage. Zoomed globes paint past their layout box, so the
  /// whole stage is clipped to its frame and never covers the HUD strip.
  Widget _globeArea(BuildContext context, List<GlobeNode> nodes,
      {bool compact = false}) {
    final atlas = countries;
    return ClipRect(
        key: const Key('globe-stage'),
        child: Stack(children: [
          Positioned.fill(
            child: atlas == null
                ? Center(
                    child: Text(atlasError ?? '正在加载 world-atlas 110m…',
                        style: TextStyle(color: context.hud.muted)))
                : AtlasGlobe(
                    key: const Key('atlas-globe'),
                    controller: controller,
                    countries: atlas,
                    nodes: nodes,
                    highlightedCodes: {for (final n in nodes) n.code},
                    selectedCode: selectedCountry,
                    onCountryTap: onGlobeCountryTap,
                  ),
          ),
          Positioned.fill(
              child: IgnorePointer(
                  child: CustomPaint(painter: _CanopyPainter(context.hud)))),
          if (compact)
            const Positioned(
                left: 6,
                top: 4,
                child: IgnorePointer(
                    child: HudLabel('World Card Atlas · Orthographic 3D')))
          else
            Positioned(
              left: 4,
              top: 0,
              child: IgnorePointer(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const HudLabel('World Card Atlas · Orthographic 3D'),
                      const SizedBox(height: 6),
                      GlassPanel(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        radius: 6,
                        child: Text(
                          atlas == null
                              ? 'Natural Earth 110m TopoJSON'
                              : 'Natural Earth 110m TopoJSON · ${atlas.length} 国 · '
                                  '${atlas.fold<int>(0, (s, c) => s + c.pointCount)} 顶点',
                          style: Hud.mono
                              .copyWith(fontSize: 10, color: context.hud.muted),
                        ),
                      ),
                    ]),
              ),
            ),
          if (!compact)
            Positioned(
              right: 4,
              top: 0,
              child: _Telemetry(
                  controller: controller, nodes: nodes, cards: filteredCards),
            ),
          if (compact)
            Positioned(
                right: 2,
                bottom: 2,
                child: _GlobeControls(controller: controller, compact: true))
          else
            Positioned(
                left: 4,
                bottom: 0,
                child: _GlobeControls(controller: controller)),
        ]));
  }
}

class _HudStrip extends StatelessWidget {
  const _HudStrip({
    this.compact = false,
    required this.allCards,
    required this.mediaCards,
    required this.codes,
    required this.mediaFilter,
    required this.onMediaFilter,
    required this.selectedCountry,
    required this.onSelectCountry,
  });

  final List<SimCard> allCards;
  final List<SimCard> mediaCards;
  final List<String> codes;
  final MediaType? mediaFilter;
  final ValueChanged<MediaType?> onMediaFilter;
  final String? selectedCountry;
  final ValueChanged<String?> onSelectCountry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    int count(MediaType m) => allCards.where((c) => c.mediaType == m).length;
    final media = [
      HudPill(
        key: const Key('media-all'),
        label: '全部介质',
        count: allCards.length,
        selected: mediaFilter == null,
        onTap: () => onMediaFilter(null),
      ),
      for (final m in MediaType.values)
        HudPill(
          key: Key('media-${m.name}'),
          label: m.label,
          count: count(m),
          color: context.hud.mediaColor(m),
          selected: mediaFilter == m,
          onTap: () => onMediaFilter(mediaFilter == m ? null : m),
        ),
    ];
    final countries = [
      HudPill(
        key: const Key('country-all'),
        label: 'ALL',
        count: mediaCards.length,
        color: context.hud.fg,
        selected: selectedCountry == null,
        onTap: () => onSelectCountry(null),
      ),
      for (final code in codes)
        HudPill(
          key: Key('country-$code'),
          label: code,
          count: mediaCards.where((c) => c.countryCode == code).length,
          color: context.hud.amber,
          selected: selectedCountry == code,
          onTap: () => onSelectCountry(code),
        ),
    ];
    if (compact) {
      Widget row(String label, List<Widget> pills, Key key) => Row(children: [
            SizedBox(
                width: 38,
                child: Text(label,
                    style: Hud.mono.copyWith(
                        fontSize: 10,
                        letterSpacing: 1.2,
                        color: context.hud.dim))),
            Expanded(
              child: SingleChildScrollView(
                key: key,
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final p in pills)
                    Padding(padding: const EdgeInsets.only(right: 2), child: p),
                ]),
              ),
            ),
          ]);
      return GlassPanel(
        key: const Key('hud-strip'),
        padding: const EdgeInsets.fromLTRB(10, 2, 4, 2),
        radius: 16,
        child: Column(children: [
          row('介质', media, const Key('media-row')),
          Container(height: 1, color: context.hud.glassEdge),
          row('聚焦', countries, const Key('country-row')),
        ]),
      );
    }
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      radius: 999,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 8,
        spacing: 12,
        children: [
          Wrap(spacing: 6, runSpacing: 6, children: media),
          Wrap(spacing: 6, runSpacing: 6, children: countries),
        ],
      ),
    );
  }
}

class _Telemetry extends StatelessWidget {
  const _Telemetry(
      {required this.controller,
      required this.nodes,
      required this.cards,
      this.compact = false});

  final bool compact;

  final GlobeController controller;
  final List<GlobeNode> nodes;
  final List<SimCard> cards;

  @override
  Widget build(BuildContext context) {
    final sorted = [...cards]
      ..sort((a, b) => a.nextDeadlineDate.compareTo(b.nextDeadlineDate));
    final nearest = sorted.isEmpty ? null : sorted.first;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final visible = nodes.where((n) {
          final l = (n.lon - controller.centerLon) * math.pi / 180;
          final p = n.lat * math.pi / 180,
              p0 = controller.centerLat * math.pi / 180;
          return math.sin(p0) * math.sin(p) +
                  math.cos(p0) * math.cos(p) * math.cos(l) >
              0;
        }).length;
        Widget row(String k, String v, {Color? color}) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                    width: 64,
                    child: Text(k,
                        style: Hud.mono
                            .copyWith(fontSize: 10, color: context.hud.dim))),
                Text(v,
                    style: Hud.mono.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: color ?? context.hud.fg)),
              ]),
            );
        final nearestText = nearest == null
            ? '—'
            : '${nearest.carrierName} · ${nearest.daysRemaining()}d';
        final nearestColor = nearest == null
            ? context.hud.fg
            : context.hud.tierColor(nearest.urgency());
        if (compact) {
          Widget cell(String k, String v, {Color? color}) => Expanded(
                child: Container(
                  margin: const EdgeInsets.all(3),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: context.hud.well,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: context.hud.glassEdge),
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(k,
                            style: Hud.mono.copyWith(
                                fontSize: 9.5,
                                letterSpacing: 1.2,
                                color: context.hud.dim)),
                        const SizedBox(height: 3),
                        Text(v,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Hud.mono.copyWith(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: color ?? context.hud.fg)),
                      ]),
                ),
              );
          return GlassPanel(
            key: const Key('telemetry'),
            padding: const EdgeInsets.fromLTRB(9, 10, 9, 9),
            radius: 16,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 4),
                  child: HudLabel('Telemetry')),
              Row(children: [
                cell('CENTER',
                    '${formatLon(controller.centerLon)} ${formatLat(controller.centerLat)}'),
                cell(
                    'ZOOM',
                    '${controller.zoom.toStringAsFixed(2)}x'
                        '${controller.spinning ? ' · SPIN' : ''}'),
              ]),
              Row(children: [
                cell('NODES', '$visible / ${nodes.length} · ${cards.length} 卡'),
                cell(
                    '最近到期',
                    nearest == null
                        ? '—'
                        : '${nearest.daysRemaining()}d · ${nearest.carrierName}',
                    color: nearestColor),
              ]),
            ]),
          );
        }
        return GlassPanel(
          key: const Key('telemetry'),
          padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const HudLabel('Telemetry'),
            const SizedBox(height: 6),
            row('CENTER',
                '${formatLon(controller.centerLon)}  ${formatLat(controller.centerLat)}'),
            row(
                'ZOOM',
                '${controller.zoom.toStringAsFixed(2)}x'
                    '${controller.spinning ? '  · AUTO-SPIN' : ''}'),
            row('NODES',
                '$visible 可见 / ${nodes.length} 节点 · ${cards.length} 卡'),
            row('最近到期', nearestText, color: nearestColor),
          ]),
        );
      },
    );
  }
}

class _GlobeControls extends StatelessWidget {
  const _GlobeControls({required this.controller, this.compact = false});

  final bool compact;

  final GlobeController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          Widget btn(String label, VoidCallback onTap,
                  {Key? key, bool on = false}) =>
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: InkWell(
                  key: key,
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: on ? context.hud.sky.withValues(alpha: .25) : null,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: context.hud.isDark
                              ? const Color(0x1FFFFFFF)
                              : context.hud.wellEdge),
                    ),
                    child: Text(label,
                        style: Hud.mono.copyWith(
                            fontSize: 11,
                            color: on ? context.hud.sky : context.hud.fg)),
                  ),
                ),
              );
          if (compact) {
            Widget round(IconData icon, String tip, VoidCallback onTap,
                    {Key? key, bool on = false}) =>
                SizedBox.square(
                  dimension: Hud.minTap,
                  child: IconButton(
                    key: key,
                    tooltip: tip,
                    onPressed: onTap,
                    style: IconButton.styleFrom(
                      backgroundColor: on
                          ? context.hud.sky.withValues(alpha: .22)
                          : context.hud.control,
                      side: BorderSide(color: context.hud.glassRim),
                    ),
                    icon: Icon(icon,
                        size: 20, color: on ? context.hud.sky : context.hud.fg),
                  ),
                );
            return Column(mainAxisSize: MainAxisSize.min, children: [
              round(controller.spinning ? Icons.pause : Icons.play_arrow,
                  controller.spinning ? '暂停自转' : '开始自转', controller.toggleSpin,
                  key: const Key('spin-toggle'), on: controller.spinning),
              const SizedBox(height: 6),
              round(Icons.add, '放大', () => controller.zoomBy(1.15),
                  key: const Key('zoom-in')),
              const SizedBox(height: 6),
              round(Icons.remove, '缩小', () => controller.zoomBy(1 / 1.15),
                  key: const Key('zoom-out')),
              const SizedBox(height: 6),
              round(Icons.center_focus_strong, '复位', controller.reset,
                  key: const Key('globe-reset')),
            ]);
          }
          return GlassPanel(
            padding: const EdgeInsets.all(6),
            radius: 12,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              btn(controller.spinning ? '◉ 自转中' : '○ 已暂停',
                  controller.toggleSpin,
                  key: const Key('spin-toggle'), on: controller.spinning),
              btn('+', () => controller.zoomBy(1.15)),
              btn('−', () => controller.zoomBy(1 / 1.15)),
              btn('复位', controller.reset),
            ]),
          );
        },
      );
}

class _RadarDrawer extends StatelessWidget {
  const _RadarDrawer(
      {required this.cards, required this.onCheckIn, this.compact = false});

  final bool compact;

  final List<SimCard> cards;
  final ValueChanged<SimCard> onCheckIn;

  @override
  Widget build(BuildContext context) {
    final sorted = [...cards]
      ..sort((a, b) => a.nextDeadlineDate.compareTo(b.nextDeadlineDate));
    final p1 = cards.where((c) => c.urgency() == UrgencyTier.p1).length;
    final p2 = cards.where((c) => c.urgency() == UrgencyTier.p2).length;
    final monthly = cards.fold<double>(0, (s, c) => s + c.monthlyCny);
    Widget radarItem(SimCard c) {
      final tier = c.urgency();
      final color = context.hud.tierColor(tier);
      return Container(
        padding: EdgeInsets.fromLTRB(
            10, compact ? 4 : 10, compact ? 2 : 10, compact ? 4 : 10),
        decoration: BoxDecoration(
          color: context.hud.well,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.hud.wellEdge),
        ),
        child: Row(children: [
          Text(c.countryCode,
              style: Hud.mono.copyWith(
                  fontSize: 11,
                  color: context.hud.muted,
                  fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.carrierName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              Text('${c.keepAliveType.verb} · ${c.hostName} · ${c.slotDetail}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: context.hud.dim)),
            ]),
          ),
          _Badge('${tier.code} · ${c.daysRemaining()}d', color),
          const SizedBox(width: 6),
          IconButton(
            key: Key('radar-check-${c.id}'),
            tooltip: '保号打卡',
            visualDensity: compact ? null : VisualDensity.compact,
            constraints: compact
                ? const BoxConstraints.tightFor(
                    width: Hud.minTap, height: Hud.minTap)
                : const BoxConstraints(),
            padding: const EdgeInsets.all(4),
            onPressed: () => onCheckIn(c),
            icon: Icon(Icons.check, size: 18, color: context.hud.emerald),
          ),
        ]),
      );
    }

    return GlassPanel(
      padding: const EdgeInsets.all(14),
      radius: 18,
      tint:
          context.hud.isDark ? const Color(0xB30B1222) : context.hud.glassTint,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: HudLabel('Keep-Alive Radar', color: context.hud.amber)),
          _Badge('P1: $p1', context.hud.rose),
          const SizedBox(width: 6),
          _Badge('P2: $p2', context.hud.amber),
        ]),
        const SizedBox(height: 4),
        Text('按保号死线排序 · P1≤15天 · P2≤60天',
            style: TextStyle(fontSize: 11, color: context.hud.dim)),
        const SizedBox(height: 10),
        if (compact)
          sorted.isEmpty
              ? Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                      child: Text('当前筛选无卡片',
                          style: TextStyle(color: context.hud.dim))))
              : Column(children: [
                  for (final c in sorted)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: radarItem(c)),
                ])
        else
          Expanded(
            child: sorted.isEmpty
                ? Center(
                    child: Text('当前筛选无卡片',
                        style: TextStyle(color: context.hud.dim)))
                : ListView.separated(
                    itemCount: sorted.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => radarItem(sorted[i]),
                  ),
          ),
        Divider(color: context.hud.line),
        Text('月均成本 ¥${monthly.toStringAsFixed(2)} / 月',
            style: Hud.mono.copyWith(fontSize: 12, color: context.hud.muted)),
      ]),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .16),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: .45)),
        ),
        child: Text(text,
            style: Hud.mono.copyWith(
                fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
      );
}

/// Outer cockpit bezel: chamfered capsule outline with corner brackets.
class _CockpitFramePainter extends CustomPainter {
  const _CockpitFramePainter(this.p);

  final HudPalette p;

  @override
  void paint(Canvas canvas, Size size) {
    const c = 26.0;
    final w = size.width, h = size.height;
    final frame = Path()
      ..moveTo(c, 0)
      ..lineTo(w - c, 0)
      ..lineTo(w, c)
      ..lineTo(w, h - c * 2)
      ..quadraticBezierTo(w, h, w - c * 3, h)
      ..lineTo(c * 3, h)
      ..quadraticBezierTo(0, h, 0, h - c * 2)
      ..lineTo(0, c)
      ..close();
    canvas.drawPath(
      frame,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: p.stageGradient,
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
        frame,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = p.sky.withValues(alpha: .28));
    final bracket = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = p.sky.withValues(alpha: .7);
    canvas.drawPath(
        Path()
          ..moveTo(c + 30, 0)
          ..lineTo(c, 0)
          ..lineTo(0, c)
          ..lineTo(0, c + 30),
        bracket);
    canvas.drawPath(
        Path()
          ..moveTo(w - c - 30, 0)
          ..lineTo(w - c, 0)
          ..lineTo(w, c)
          ..lineTo(w, c + 30),
        bracket);
  }

  @override
  bool shouldRepaint(_CockpitFramePainter oldDelegate) => oldDelegate.p != p;
}

/// Canopy arc + tick marks framing the globe like a half cockpit window.
class _CanopyPainter extends CustomPainter {
  const _CanopyPainter(this.p);

  final HudPalette p;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .5);
    final r = math.min(size.width, size.height) * .49;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = p.sky.withValues(alpha: .22);
    canvas.drawArc(Rect.fromCircle(center: center, radius: r), math.pi * .85,
        math.pi * 1.3, false, arc);
    final tick = Paint()
      ..strokeWidth = 1
      ..color = p.sky.withValues(alpha: .35);
    for (var i = 0; i <= 36; i++) {
      final a = math.pi * .85 + math.pi * 1.3 * i / 36;
      final len = i % 6 == 0 ? 10.0 : 4.0;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(center + dir * r, center + dir * (r + len), tick);
    }
    final base = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [p.stageFade.withValues(alpha: 0), p.stageFade],
      ).createShader(
          Rect.fromLTWH(0, size.height * .82, size.width, size.height * .18));
    canvas.drawRect(
        Rect.fromLTWH(0, size.height * .82, size.width, size.height * .18),
        base);
  }

  @override
  bool shouldRepaint(_CanopyPainter oldDelegate) => oldDelegate.p != p;
}
