import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'globe_controller.dart';
import 'orthographic.dart';
import 'topojson.dart';

const worldAtlasAsset = 'assets/geo/countries-110m.json';

Future<List<GeoCountry>> loadWorldAtlas([AssetBundle? bundle]) async =>
    decodeWorldAtlas(await (bundle ?? rootBundle).loadString(worldAtlasAsset));

class GlobeNode {
  const GlobeNode({
    required this.code,
    required this.lon,
    required this.lat,
    required this.count,
    required this.color,
  });

  final String code;
  final double lon;
  final double lat;
  final int count;
  final Color color;
}

/// Node markers that survive backface culling for the given projection.
List<(GlobeNode, Offset)> visibleNodes(
    Orthographic projection, List<GlobeNode> nodes) {
  final out = <(GlobeNode, Offset)>[];
  for (final node in nodes) {
    final p = projection.project(node.lon, node.lat);
    if (p != null) out.add((node, p));
  }
  return out;
}

Orthographic projectionFor(GlobeController c, Size size) => Orthographic(
      centerLon: c.centerLon,
      centerLat: c.centerLat,
      radius: math.min(size.width, size.height) * 0.42 * c.zoom,
      origin: size.center(Offset.zero),
    );

/// Real-geometry orthographic globe: world-atlas polygons, far-hemisphere
/// culling, drag rotation, auto-spin, wheel zoom, tap-to-select country/node.
class AtlasGlobe extends StatefulWidget {
  const AtlasGlobe({
    super.key,
    required this.controller,
    required this.countries,
    required this.nodes,
    this.highlightedCodes = const {},
    this.selectedCode,
    this.onCountryTap,
  });

  final GlobeController controller;
  final List<GeoCountry> countries;
  final List<GlobeNode> nodes;
  final Set<String> highlightedCodes;
  final String? selectedCode;
  final void Function(String? iso2, String name, double lon, double lat)?
      onCountryTap;

  @override
  State<AtlasGlobe> createState() => _AtlasGlobeState();
}

class _AtlasGlobeState extends State<AtlasGlobe>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(widget.controller.tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _handleTap(Offset local, Size size) {
    final projection = projectionFor(widget.controller, size);
    for (final (node, pos) in visibleNodes(projection, widget.nodes)) {
      if ((pos - local).distance < 16) {
        widget.onCountryTap?.call(node.code, node.code, node.lon, node.lat);
        return;
      }
    }
    final geo = projection.invert(local);
    if (geo == null) return;
    final (lon, lat) = geo;
    for (final country in widget.countries) {
      if (country.contains(lon, lat)) {
        final (clon, clat) = country.centroid;
        widget.onCountryTap?.call(country.iso2, country.name, clon, clat);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      return Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            // Claim the wheel so the page behind the globe does not scroll.
            GestureBinding.instance.pointerSignalResolver.register(
                event,
                (e) => c.zoomBy(
                    (e as PointerScrollEvent).scrollDelta.dy > 0 ? 0.9 : 1.1));
          }
        },
        child: MouseRegion(
          cursor: c.dragging
              ? SystemMouseCursors.grabbing
              : SystemMouseCursors.grab,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => c.setDragging(true),
            onPanUpdate: (d) {
              final r = projectionFor(c, size).radius;
              c.dragBy(d.delta.dx / r * 180 / math.pi,
                  d.delta.dy / r * 180 / math.pi);
            },
            onPanEnd: (_) => c.setDragging(false),
            onPanCancel: () => c.setDragging(false),
            onTapUp: (d) => _handleTap(d.localPosition, size),
            child: CustomPaint(
              size: size,
              painter: GlobePainter(
                controller: c,
                countries: widget.countries,
                nodes: widget.nodes,
                highlightedCodes: widget.highlightedCodes,
                selectedCode: widget.selectedCode,
              ),
            ),
          ),
        ),
      );
    });
  }
}

class GlobePainter extends CustomPainter {
  GlobePainter({
    required this.controller,
    required this.countries,
    required this.nodes,
    required this.highlightedCodes,
    required this.selectedCode,
  }) : super(repaint: controller);

  final GlobeController controller;
  final List<GeoCountry> countries;
  final List<GlobeNode> nodes;
  final Set<String> highlightedCodes;
  final String? selectedCode;

  static final List<List<(double, double)>> _graticule = [
    for (var lon = -180.0; lon < 180; lon += 15)
      [for (var lat = -90.0; lat <= 90; lat += 3) (lon, lat)],
    for (var lat = -75.0; lat <= 75; lat += 15)
      [for (var lon = -180.0; lon <= 180; lon += 3) (lon, lat)],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final proj = projectionFor(controller, size);
    final o = proj.origin, r = proj.radius;
    final sphere = Rect.fromCircle(center: o, radius: r);

    canvas.drawCircle(
      o,
      r * 1.12,
      Paint()
        ..shader = RadialGradient(colors: [
          const Color(0xFF38BDF8).withValues(alpha: .22),
          const Color(0xFF38BDF8).withValues(alpha: 0),
        ], stops: const [
          .82,
          1
        ]).createShader(Rect.fromCircle(center: o, radius: r * 1.12)),
    );
    canvas.drawCircle(
      o,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-.35, -.4),
          radius: 1.1,
          colors: [Color(0xFF12305A), Color(0xFF071530), Color(0xFF030814)],
          stops: [0, .6, 1],
        ).createShader(sphere),
    );

    canvas.save();
    canvas.clipPath(Path()..addOval(sphere));

    final grid = Path();
    for (final line in _graticule) {
      proj.visiblePolyline(line, grid);
    }
    canvas.drawPath(
        grid,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .6
          ..color = const Color(0xFF38BDF8).withValues(alpha: .14));

    final landFill = Paint()..color = const Color(0xFF1B3354);
    final activeFill = Paint()
      ..color = const Color(0xFF0EA5E9).withValues(alpha: .55);
    final selectedFill = Paint()
      ..color = const Color(0xFFFBBF24).withValues(alpha: .75);
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .7
      ..color = const Color(0xFF7DD3FC).withValues(alpha: .35);

    for (final country in countries) {
      final path = Path()..fillType = PathFillType.evenOdd;
      var any = false;
      for (final polygon in country.polygons) {
        for (final ring in polygon) {
          if (proj.clippedRing(ring, into: path) != null) any = true;
        }
      }
      if (!any) continue;
      final code = country.iso2;
      final fill = code != null && code == selectedCode
          ? selectedFill
          : code != null && highlightedCodes.contains(code)
              ? activeFill
              : landFill;
      canvas.drawPath(path, fill);
      canvas.drawPath(path, border);
    }

    // Night-side shading for depth.
    canvas.drawCircle(
      o,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.45, -.45),
          radius: 1.35,
          colors: [Colors.transparent, Colors.black.withValues(alpha: .55)],
          stops: const [.55, 1],
        ).createShader(sphere),
    );
    canvas.restore();

    canvas.drawCircle(
        o,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0xFF7DD3FC).withValues(alpha: .45));

    for (final (node, p) in visibleNodes(proj, nodes)) {
      _paintNode(canvas, node, p);
    }
  }

  void _paintNode(Canvas canvas, GlobeNode node, Offset p) {
    final selected = node.code == selectedCode;
    canvas.drawCircle(p, selected ? 11 : 8,
        Paint()..color = node.color.withValues(alpha: .25));
    canvas.drawCircle(p, 4.5, Paint()..color = node.color);
    canvas.drawCircle(
        p,
        4.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = Colors.white);
    final tp = TextPainter(
      text: TextSpan(
        text: '${node.code}  ${node.count}',
        style: const TextStyle(
            color: Colors.white,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            fontFamily: 'monospace'),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(p.dx + 9, p.dy - 9, tp.width + 12, 18),
      const Radius.circular(9),
    );
    canvas.drawRRect(
        rect, Paint()..color = const Color(0xFF020617).withValues(alpha: .82));
    canvas.drawRRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = (selected ? const Color(0xFFFBBF24) : node.color)
              .withValues(alpha: .8));
    tp.paint(canvas, Offset(p.dx + 15, p.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant GlobePainter old) =>
      old.countries != countries ||
      old.nodes != nodes ||
      old.selectedCode != selectedCode ||
      old.highlightedCodes != highlightedCodes;
}
