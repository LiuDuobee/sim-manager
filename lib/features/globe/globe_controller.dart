import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

import 'orthographic.dart';

/// View state of the atlas globe: rotation center, zoom, auto-spin and the
/// fly-to tween. The globe widget drives [tick] from a Ticker.
class GlobeController extends ChangeNotifier {
  GlobeController({
    this.centerLon = 110,
    this.centerLat = 24,
    this.zoom = 1,
    this.spinning = true,
  });

  static const flyDuration = Duration(milliseconds: 650);
  static const spinDegreesPerSecond = 6.0;

  /// Wheel / button zoom range. Above 1.0x the sphere is larger than the
  /// stage; the HUD stage clips it to its frame (see `HudStage`).
  static const minZoom = 1.0, maxZoom = 2.0;

  double centerLon;
  double centerLat;
  double zoom;
  bool spinning;
  bool dragging = false;

  _Flight? _flight;
  Duration? _last;

  bool get isFlying => _flight != null;

  void tick(Duration elapsed) {
    final dt = _last == null
        ? 0.0
        : (elapsed - _last!).inMicroseconds / Duration.microsecondsPerSecond;
    _last = elapsed;
    final flight = _flight;
    if (flight != null) {
      flight.elapsed += dt;
      final t = (flight.elapsed / (flyDuration.inMilliseconds / 1000))
          .clamp(0.0, 1.0);
      final e = Curves.easeOutCubic.transform(t);
      centerLon = _normLon(flight.fromLon + flight.dLon * e);
      centerLat = flight.fromLat + (flight.toLat - flight.fromLat) * e;
      zoom = flight.fromZoom + (flight.toZoom - flight.fromZoom) * e;
      if (t >= 1) _flight = null;
      notifyListeners();
    } else if (spinning && !dragging && dt > 0) {
      centerLon = _normLon(centerLon + spinDegreesPerSecond * dt);
      notifyListeners();
    }
  }

  void flyTo(double lon, double lat, {double? zoom}) {
    _flight = _Flight(
      fromLon: centerLon,
      fromLat: centerLat,
      dLon: wrapLonDelta(lon - centerLon),
      toLat: lat.clamp(-80.0, 80.0),
      fromZoom: this.zoom,
      toZoom: (zoom ?? math.max(this.zoom, 1.35)).clamp(minZoom, maxZoom),
    );
    spinning = false;
    notifyListeners();
  }

  void dragBy(double dLonDegrees, double dLatDegrees) {
    _flight = null;
    centerLon = _normLon(centerLon - dLonDegrees);
    centerLat = (centerLat + dLatDegrees).clamp(-80.0, 80.0);
    notifyListeners();
  }

  void setDragging(bool value) {
    dragging = value;
    notifyListeners();
  }

  void toggleSpin() {
    spinning = !spinning;
    notifyListeners();
  }

  void zoomBy(double factor) {
    zoom = (zoom * factor).clamp(minZoom, maxZoom);
    notifyListeners();
  }

  void reset() => flyTo(110, 24, zoom: 1);

  static double _normLon(double lon) => wrapLonDelta(lon);
}

class _Flight {
  _Flight({
    required this.fromLon,
    required this.fromLat,
    required this.dLon,
    required this.toLat,
    required this.fromZoom,
    required this.toZoom,
  });

  final double fromLon, fromLat, dLon, toLat, fromZoom, toZoom;
  double elapsed = 0;
}
