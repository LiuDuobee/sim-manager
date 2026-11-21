import 'dart:math' as math;
import 'dart:ui';

const _deg = math.pi / 180;

/// Orthographic projection: lon/lat → unit sphere → rotate so that
/// (centerLon, centerLat) faces the viewer → drop the depth axis.
class Orthographic {
  Orthographic({
    required this.centerLon,
    required this.centerLat,
    required this.radius,
    required this.origin,
  }) {
    final l0 = centerLon * _deg, p0 = centerLat * _deg;
    final cl = math.cos(l0), sl = math.sin(l0);
    final cp = math.cos(p0), sp = math.sin(p0);
    _cx = cp * cl;
    _cy = cp * sl;
    _cz = sp;
    _ex = -sl;
    _ey = cl;
    _nx = -sp * cl;
    _ny = -sp * sl;
    _nz = cp;
  }

  final double centerLon;
  final double centerLat;
  final double radius;
  final Offset origin;

  // View basis: c = toward viewer, e = screen-right (east), n = screen-up.
  late final double _cx, _cy, _cz, _ex, _ey, _nx, _ny, _nz;

  /// Returns (x, y, depth). depth = cos(angular distance from center);
  /// depth > 0 ⇔ center angle < 90° ⇔ point is on the visible hemisphere.
  (double, double, double) projectRaw(double lon, double lat) {
    final l = lon * _deg, p = lat * _deg;
    final cp = math.cos(p);
    final px = cp * math.cos(l), py = cp * math.sin(l), pz = math.sin(p);
    final x = px * _ex + py * _ey;
    final y = px * _nx + py * _ny + pz * _nz;
    final z = px * _cx + py * _cy + pz * _cz;
    return (x, y, z);
  }

  Offset toScreen(double x, double y) =>
      Offset(origin.dx + x * radius, origin.dy - y * radius);

  /// Screen position, or null when the point is on the far hemisphere.
  Offset? project(double lon, double lat) {
    final (x, y, z) = projectRaw(lon, lat);
    if (z <= 0) return null;
    return toScreen(x, y);
  }

  bool isVisible(double lon, double lat) => projectRaw(lon, lat).$3 > 0;

  /// Screen point → (lon, lat) on the visible hemisphere, or null if outside.
  (double, double)? invert(Offset screen) {
    final x = (screen.dx - origin.dx) / radius;
    final y = -(screen.dy - origin.dy) / radius;
    final r2 = x * x + y * y;
    if (r2 > 1) return null;
    final z = math.sqrt(1 - r2);
    final px = x * _ex + y * _nx + z * _cx;
    final py = x * _ey + y * _ny + z * _cy;
    final pz = y * _nz + z * _cz;
    return (math.atan2(py, px) / _deg, math.asin(pz.clamp(-1.0, 1.0)) / _deg);
  }

  /// Builds a closed path for a ring, clipped to the visible hemisphere.
  /// Edges crossing the horizon are cut at the exact great-circle crossing;
  /// far-side stretches are replaced by the limb (circle edge) so fills stay
  /// closed. Returns null when the whole ring is on the far side.
  Path? clippedRing(List<double> ring, {Path? into}) {
    final n = ring.length ~/ 2;
    if (n < 3) return null;
    final xs = List<double>.filled(n, 0), ys = List<double>.filled(n, 0);
    final zs = List<double>.filled(n, 0);
    var anyVisible = false;
    for (var i = 0; i < n; i++) {
      final (x, y, z) = projectRaw(ring[i * 2], ring[i * 2 + 1]);
      xs[i] = x;
      ys[i] = y;
      zs[i] = z;
      if (z > 0) anyVisible = true;
    }
    if (!anyVisible) return null;
    final path = into ?? Path();
    var started = false;
    void emit(double x, double y) {
      final o = toScreen(x, y);
      if (started) {
        path.lineTo(o.dx, o.dy);
      } else {
        path.moveTo(o.dx, o.dy);
        started = true;
      }
    }

    void emitLimb(double x, double y) {
      final len = math.sqrt(x * x + y * y);
      if (len < 1e-12) return;
      emit(x / len, y / len);
    }

    for (var i = 0; i < n; i++) {
      final j = (i + 1) % n;
      final zi = zs[i], zj = zs[j];
      if (zi > 0) {
        emit(xs[i], ys[i]);
      } else {
        emitLimb(xs[i], ys[i]);
      }
      if ((zi > 0) != (zj > 0)) {
        final t = zi / (zi - zj);
        emitLimb(xs[i] + (xs[j] - xs[i]) * t, ys[i] + (ys[j] - ys[i]) * t);
      }
    }
    path.close();
    return path;
  }

  /// Open polyline clipped to the visible hemisphere (for graticules).
  void visiblePolyline(List<(double, double)> points, Path into) {
    var drawing = false;
    for (final (lon, lat) in points) {
      final (x, y, z) = projectRaw(lon, lat);
      final o = toScreen(x, y);
      if (z > 0) {
        drawing ? into.lineTo(o.dx, o.dy) : into.moveTo(o.dx, o.dy);
        drawing = true;
      } else {
        drawing = false;
      }
    }
  }
}

/// Shortest signed longitude delta in degrees, in (-180, 180].
double wrapLonDelta(double delta) {
  var d = (delta + 180) % 360;
  if (d < 0) d += 360;
  return d - 180;
}
