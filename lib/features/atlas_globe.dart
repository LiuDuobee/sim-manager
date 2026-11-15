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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onScaleStart: (details) {
        _dragStart = details.focalPoint;
        _rotationStart = _rotation;
      },
      onScaleUpdate: (details) {
        final start = _dragStart;
        if (start == null) return;
        setState(() {
          _rotation = _rotationStart + (details.focalPoint.dx - start.dx) / 180;
          _scale = (_scale * details.scale).clamp(.82, 1.65);
        });
      },
      onScaleEnd: (_) => _dragStart = null,
      child: CustomPaint(
        painter: _AtlasGlobePainter(
          rotation: _rotation,
          scale: _scale,
          countryCodes: widget.countryCodes,
          onCountrySelected: widget.onCountrySelected,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _AtlasGlobePainter extends CustomPainter {
  _AtlasGlobePainter({
    required this.rotation,
    required this.scale,
    required this.countryCodes,
    required this.onCountrySelected,
  });

  final double rotation;
  final double scale;
  final List<String> countryCodes;
  final ValueChanged<String> onCountrySelected;

  static const _nodes = <String, Offset>{
    'CN': Offset(.68, -.04),
    'GB': Offset(.42, -.53),
    'HK': Offset(.70, .04),
    'US': Offset(.17, -.12),
    'JP': Offset(.79, -.02),
  };

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * .34 * scale;
    final glow = Paint()
      ..shader = RadialGradient(
        colors: const [Color(0x3346B7FF), Color(0x0010182A)],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 1.45));
    canvas.drawCircle(center, radius * 1.45, glow);

    final sphere = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-.35, -.42),
        radius: 1.05,
        colors: [Color(0xFF1E3854), Color(0xFF0D1726), Color(0xFF070A11)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, sphere);

    final line = Paint()
      ..color = const Color(0x443F82B8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = -3; i <= 3; i++) {
      final y = center.dy + radius * i / 4;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(center.dx, y),
          width: radius * 2 * math.sqrt(math.max(0, 1 - (i / 4) * (i / 4))),
          height: radius * .22,
        ),
        line,
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
        line,
      );
    }

    final land = Paint()
      ..color = const Color(0xAA2E6E71)
      ..style = PaintingStyle.fill;
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
            center.dx + point.dx * radius, center.dy + point.dy * radius);
      }
      path.close();
      canvas.drawPath(path, land);
    }

    for (final code in countryCodes) {
      final node = _nodes[code];
      if (node == null) continue;
      final x = center.dx +
          (node.dx - .5) * radius * 1.7 +
          math.sin(rotation) * radius * .12;
      final y = center.dy + node.dy * radius * 1.7;
      final dot = Paint()..color = const Color(0xFFFFB45C);
      canvas.drawCircle(Offset(x, y), 5, dot);
      canvas.drawCircle(
        Offset(x, y),
        11,
        Paint()
          ..color = const Color(0x55FFB45C)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool hitTest(Offset position) {
    for (final entry in _nodes.entries) {
      if (!countryCodes.contains(entry.key)) continue;
      onCountrySelected(entry.key);
      return true;
    }
    return false;
  }

  @override
  bool shouldRepaint(covariant _AtlasGlobePainter oldDelegate) =>
      oldDelegate.rotation != rotation ||
      oldDelegate.scale != scale ||
      oldDelegate.countryCodes != countryCodes;
}
