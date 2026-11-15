import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

class AtlasGlobe extends StatefulWidget {
  const AtlasGlobe({
    super.key,
    required this.countryCodes,
    required this.onCountrySelected,
  });

  final List<String> countryCodes;
  final ValueChanged<String> onCountrySelected;

  @override
  State<AtlasGlobe> createState() => _AtlasGlobeState();
}

class _AtlasGlobeState extends State<AtlasGlobe> {
  double _rotation = -0.55;
  double _scale = 1;
  Offset? _dragStart;
  double _rotationStart = 0;
  double _scaleStart = 1;
  Timer? _timer;
  bool _autoRotate = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted || !_autoRotate || _dragStart != null) return;
      setState(() => _rotation += 0.0025);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _rotation = -0.55;
      _scale = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        return Stack(
          children: [
            GestureDetector(
              onDoubleTap: _reset,
              onScaleStart: (details) {
                _dragStart = details.focalPoint;
                _rotationStart = _rotation;
                _scaleStart = _scale;
                setState(() => _autoRotate = false);
              },
              onScaleUpdate: (details) {
                final start = _dragStart;
                if (start == null) return;
                setState(() {
                  _rotation =
                      _rotationStart + (details.focalPoint.dx - start.dx) / 180;
                  _scale = (_scaleStart * details.scale).clamp(.72, 1.8);
                });
              },
              onScaleEnd: (_) {
                _dragStart = null;
                setState(() => _autoRotate = true);
              },
              onTapUp: (details) {
                final code = _nearestCountry(
                  details.localPosition,
                  Size(width, height),
                );
                if (code != null) widget.onCountrySelected(code);
              },
              child: CustomPaint(
                painter: _AtlasGlobePainter(
                  rotation: _rotation,
                  scale: _scale,
                  countryCodes: widget.countryCodes,
                ),
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              left: 16,
              bottom: 14,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xCC0A1019),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x445C91B9)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () =>
                          setState(() => _autoRotate = !_autoRotate),
                      tooltip: _autoRotate ? '暂停自转' : '开始自转',
                      icon: Icon(
                        _autoRotate ? Icons.pause : Icons.play_arrow,
                        color: const Color(0xFF8FD8FF),
                        size: 18,
                      ),
                    ),
                    IconButton(
                      onPressed: _reset,
                      tooltip: '复位',
                      icon: const Icon(
                        Icons.center_focus_strong,
                        color: Color(0xFF8FD8FF),
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 16,
              bottom: 17,
              child: Text(
                'LAT 35.68° N  ·  LON ${(_rotation * 57.3).toStringAsFixed(2)}°  ·  ${_scale.toStringAsFixed(2)}×',
                style: const TextStyle(
                  color: Color(0xFF718CA5),
                  fontSize: 9,
                  letterSpacing: 0.8,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String? _nearestCountry(Offset position, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * .34 * _scale;
    String? selected;
    var distance = double.infinity;
    for (final entry in _AtlasGlobePainter.nodes.entries) {
      if (!widget.countryCodes.contains(entry.key)) continue;
      final point = _AtlasGlobePainter.projectNode(
        center,
        radius,
        _rotation,
        entry.value,
      );
      final nextDistance = (position - point).distance;
      if (nextDistance < distance && nextDistance < 28) {
        selected = entry.key;
        distance = nextDistance;
      }
    }
    return selected;
  }
}

class _AtlasGlobePainter extends CustomPainter {
  _AtlasGlobePainter({
    required this.rotation,
    required this.scale,
    required this.countryCodes,
  });

  final double rotation;
  final double scale;
  final List<String> countryCodes;

  static const nodes = <String, Offset>{
    'CN': Offset(.68, -.04),
    'GB': Offset(.42, -.53),
    'HK': Offset(.70, .04),
    'US': Offset(.17, -.12),
    'JP': Offset(.79, -.02),
    'AU': Offset(.79, .53),
    'DE': Offset(.47, -.40),
  };

  static Offset projectNode(
    Offset center,
    double radius,
    double rotation,
    Offset node,
  ) {
    return Offset(
      center.dx +
          (node.dx - .5) * radius * 1.7 +
          math.sin(rotation) * radius * .12,
      center.dy + node.dy * radius * 1.7,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * .34 * scale;
    final glow = Paint()
      ..shader = RadialGradient(
        colors: const [Color(0x5546B7FF), Color(0x0010182A)],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 1.55));
    canvas.drawCircle(center, radius * 1.55, glow);

    final sphere = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-.35, -.42),
        radius: 1.05,
        colors: [Color(0xFF1F4260), Color(0xFF0D1C2C), Color(0xFF06090F)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, sphere);

    final edge = Paint()
      ..color = const Color(0x885E9BC1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(center, radius, edge);

    final grid = Paint()
      ..color = const Color(0x443F82B8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (var i = -3; i <= 3; i++) {
      final y = center.dy + radius * i / 4;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(center.dx, y),
          width: radius * 2 * math.sqrt(math.max(0, 1 - (i / 4) * (i / 4))),
          height: radius * .22,
        ),
        grid,
      );
    }
    for (var i = 0; i < 8; i++) {
      final x = center.dx + radius * math.sin(rotation + i * math.pi / 4);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x, center.dy),
          width: radius * .18,
          height: radius * 2,
        ),
        grid,
      );
    }

    final land = Paint()
      ..color = const Color(0xAA287477)
      ..style = PaintingStyle.fill;
    final coast = Paint()
      ..color = const Color(0xAA54B9A8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final continents = [
      [
        Offset(-.58, -.35),
        Offset(-.2, -.55),
        Offset(-.02, -.25),
        Offset(-.2, .05),
        Offset(-.46, .02)
      ],
      [
        Offset(.02, -.36),
        Offset(.4, -.52),
        Offset(.7, -.3),
        Offset(.5, .02),
        Offset(.25, .02)
      ],
      [
        Offset(-.04, .1),
        Offset(.2, .08),
        Offset(.3, .45),
        Offset(.1, .7),
        Offset(-.1, .36)
      ],
      [Offset(.42, .1), Offset(.73, .1), Offset(.65, .43), Offset(.35, .35)],
    ];
    for (final points in continents) {
      final path = Path()
        ..moveTo(center.dx + points.first.dx * radius,
            center.dy + points.first.dy * radius);
      for (final point in points.skip(1)) {
        path.lineTo(
          center.dx + point.dx * radius,
          center.dy + point.dy * radius,
        );
      }
      path.close();
      canvas.drawPath(path, land);
      canvas.drawPath(path, coast);
    }

    for (final code in countryCodes) {
      final node = nodes[code];
      if (node == null) continue;
      final point = projectNode(center, radius, rotation, node);
      canvas.drawCircle(point, 11, Paint()..color = const Color(0x33FFB45C));
      canvas.drawCircle(point, 5, Paint()..color = const Color(0xFFFFB45C));
      canvas.drawCircle(
        point,
        9,
        Paint()
          ..color = const Color(0xAAFFCE83)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AtlasGlobePainter oldDelegate) =>
      oldDelegate.rotation != rotation ||
      oldDelegate.scale != scale ||
      oldDelegate.countryCodes != countryCodes;
}
