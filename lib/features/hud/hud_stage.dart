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
List<GlobeNode> buildGlobeNodes(
    List<SimCard> cards, List<GeoCountry> countries) {
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
      color: Hud.tierColor(worst),
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
    final nodes = buildGlobeNodes(filteredCards, countries ?? const []);

    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 980;
      return CustomPaint(
        painter: const _CockpitFramePainter(),
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
                    Expanded(child: _globeArea(nodes)),
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

  /// The globe stage. Zoomed globes paint past their layout box, so the
  /// whole stage is clipped to its frame and never covers the HUD strip.
  Widget _globeArea(List<GlobeNode> nodes) {
    final atlas = countries;
    return ClipRect(
        key: const Key('globe-stage'),
        child: Stack(children: [
          Positioned.fill(
            child: atlas == null
                ? Center(
                    child: Text(atlasError ?? '正在加载 world-atlas 110m…',
                        style: const TextStyle(color: Hud.muted)))
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
          const Positioned.fill(
              child:
                  IgnorePointer(child: CustomPaint(painter: _CanopyPainter()))),
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
                        style:
                            Hud.mono.copyWith(fontSize: 10, color: Hud.muted),
                      ),
                    ),
                  ]),
            ),
          ),
          Positioned(
            right: 4,
            top: 0,
            child: _Telemetry(
                controller: controller, nodes: nodes, cards: filteredCards),
          ),
          Positioned(
              left: 4,
              bottom: 0,
              child: _GlobeControls(controller: controller)),
        ]));
  }
}

class _HudStrip extends StatelessWidget {
  const _HudStrip({
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

  @override
  Widget build(BuildContext context) {
    int count(MediaType m) => allCards.where((c) => c.mediaType == m).length;
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      radius: 999,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 8,
        spacing: 12,
        children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
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
                color: Hud.mediaColor(m),
                selected: mediaFilter == m,
                onTap: () => onMediaFilter(mediaFilter == m ? null : m),
              ),
          ]),
          Wrap(spacing: 6, runSpacing: 6, children: [
            HudPill(
              key: const Key('country-all'),
              label: 'ALL',
              count: mediaCards.length,
              color: Colors.white,
              selected: selectedCountry == null,
              onTap: () => onSelectCountry(null),
            ),
            for (final code in codes)
              HudPill(
                key: Key('country-$code'),
                label: code,
                count: mediaCards.where((c) => c.countryCode == code).length,
                color: Hud.amber,
                selected: selectedCountry == code,
                onTap: () => onSelectCountry(code),
              ),
          ]),
        ],
      ),
    );
  }
}

class _Telemetry extends StatelessWidget {
  const _Telemetry(
      {required this.controller, required this.nodes, required this.cards});

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
        Widget row(String k, String v, {Color color = Colors.white}) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                    width: 64,
                    child: Text(k,
                        style:
                            Hud.mono.copyWith(fontSize: 10, color: Hud.dim))),
                Text(v,
                    style: Hud.mono.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: color)),
              ]),
            );
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
            row(
              '最近到期',
              nearest == null
                  ? '—'
                  : '${nearest.carrierName} · ${nearest.daysRemaining()}d',
              color: nearest == null
                  ? Colors.white
                  : Hud.tierColor(nearest.urgency()),
            ),
          ]),
        );
      },
    );
  }
}

class _GlobeControls extends StatelessWidget {
  const _GlobeControls({required this.controller});

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
                      color: on ? Hud.sky.withValues(alpha: .25) : null,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: .12)),
                    ),
                    child: Text(label,
                        style: Hud.mono.copyWith(
                            fontSize: 11, color: on ? Hud.sky : Colors.white)),
                  ),
                ),
              );
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
  const _RadarDrawer({required this.cards, required this.onCheckIn});

  final List<SimCard> cards;
  final ValueChanged<SimCard> onCheckIn;

  @override
  Widget build(BuildContext context) {
    final sorted = [...cards]
      ..sort((a, b) => a.nextDeadlineDate.compareTo(b.nextDeadlineDate));
    final p1 = cards.where((c) => c.urgency() == UrgencyTier.p1).length;
    final p2 = cards.where((c) => c.urgency() == UrgencyTier.p2).length;
    final monthly = cards.fold<double>(0, (s, c) => s + c.monthlyCny);
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      radius: 18,
      tint: const Color(0xB30B1222),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: HudLabel('Keep-Alive Radar', color: Hud.amber)),
          _Badge('P1: $p1', Hud.rose),
          const SizedBox(width: 6),
          _Badge('P2: $p2', Hud.amber),
        ]),
        const SizedBox(height: 4),
        const Text('按保号死线排序 · P1≤15天 · P2≤60天',
            style: TextStyle(fontSize: 11, color: Hud.dim)),
        const SizedBox(height: 10),
        Expanded(
          child: sorted.isEmpty
              ? const Center(
                  child: Text('当前筛选无卡片', style: TextStyle(color: Hud.dim)))
              : ListView.separated(
                  itemCount: sorted.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final c = sorted[i];
                    final tier = c.urgency();
                    final color = Hud.tierColor(tier);
                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0x99020617),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: .06)),
                      ),
                      child: Row(children: [
                        Text(c.countryCode,
                            style: Hud.mono.copyWith(
                                fontSize: 11,
                                color: Hud.muted,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.carrierName,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700)),
                                Text('${c.hostName} · ${c.slotDetail}',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 11, color: Hud.dim)),
                              ]),
                        ),
                        _Badge('${tier.code} · ${c.daysRemaining()}d', color),
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: '保号打卡',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(4),
                          onPressed: () => onCheckIn(c),
                          icon: const Icon(Icons.check,
                              size: 18, color: Hud.emerald),
                        ),
                      ]),
                    );
                  },
                ),
        ),
        const Divider(color: Hud.line),
        Text('月均成本 ¥${monthly.toStringAsFixed(2)} / 月',
            style: Hud.mono.copyWith(fontSize: 12, color: Hud.muted)),
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
  const _CockpitFramePainter();

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
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0A1528), Color(0xFF050B17), Color(0xFF02050C)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
        frame,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Hud.sky.withValues(alpha: .28));
    final bracket = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Hud.sky.withValues(alpha: .7);
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Canopy arc + tick marks framing the globe like a half cockpit window.
class _CanopyPainter extends CustomPainter {
  const _CanopyPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .5);
    final r = math.min(size.width, size.height) * .49;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Hud.sky.withValues(alpha: .22);
    canvas.drawArc(Rect.fromCircle(center: center, radius: r), math.pi * .85,
        math.pi * 1.3, false, arc);
    final tick = Paint()
      ..strokeWidth = 1
      ..color = Hud.sky.withValues(alpha: .35);
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
        colors: [
          Colors.transparent,
          const Color(0xFF02050C).withValues(alpha: .85)
        ],
      ).createShader(
          Rect.fromLTWH(0, size.height * .82, size.width, size.height * .18));
    canvas.drawRect(
        Rect.fromLTWH(0, size.height * .82, size.width, size.height * .18),
        base);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
