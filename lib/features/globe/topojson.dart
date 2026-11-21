import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'country_codes.dart';

/// A country decoded from world-atlas TopoJSON. Coordinates are degrees.
class GeoCountry {
  GeoCountry({
    required this.numericId,
    required this.iso2,
    required this.name,
    required this.polygons,
  }) : bounds = polygons.map(_ringBounds).toList();

  final String? numericId;
  final String? iso2;
  final String name;

  /// polygons → rings (first is exterior) → flat [lon0, lat0, lon1, lat1, ...].
  final List<List<Float64List>> polygons;
  final List<Float64List> bounds;

  static Float64List _ringBounds(List<Float64List> polygon) {
    var minLon = 180.0, minLat = 90.0, maxLon = -180.0, maxLat = -90.0;
    final ring = polygon.first;
    for (var i = 0; i < ring.length; i += 2) {
      minLon = math.min(minLon, ring[i]);
      maxLon = math.max(maxLon, ring[i]);
      minLat = math.min(minLat, ring[i + 1]);
      maxLat = math.max(maxLat, ring[i + 1]);
    }
    return Float64List.fromList([minLon, minLat, maxLon, maxLat]);
  }

  int get pointCount => polygons.fold(
      0, (s, p) => s + p.fold(0, (r, ring) => r + ring.length ~/ 2));

  /// Planar ray-casting point-in-polygon on lon/lat; antimeridian rings were
  /// unwrapped by [unwrapAntimeridian], so west-of-180° points also try +360°.
  bool contains(double lon, double lat) =>
      _contains(lon, lat) || (lon < 0 && _contains(lon + 360, lat));

  bool _contains(double lon, double lat) {
    for (var p = 0; p < polygons.length; p++) {
      final b = bounds[p];
      if (lon < b[0] || lon > b[2] || lat < b[1] || lat > b[3]) continue;
      var inside = _inRing(polygons[p].first, lon, lat);
      for (var h = 1; inside && h < polygons[p].length; h++) {
        if (_inRing(polygons[p][h], lon, lat)) inside = false;
      }
      if (inside) return true;
    }
    return false;
  }

  static bool _inRing(Float64List ring, double x, double y) {
    var inside = false;
    final n = ring.length ~/ 2;
    for (var i = 0, j = n - 1; i < n; j = i++) {
      final xi = ring[i * 2], yi = ring[i * 2 + 1];
      final xj = ring[j * 2], yj = ring[j * 2 + 1];
      if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) {
        inside = !inside;
      }
    }
    return inside;
  }

  /// Area-weighted centroid of the largest polygon (lon, lat).
  (double, double) get centroid {
    Float64List? best;
    var bestArea = -1.0;
    for (final polygon in polygons) {
      final a = _signedArea(polygon.first).abs();
      if (a > bestArea) {
        bestArea = a;
        best = polygon.first;
      }
    }
    final ring = best!;
    var cx = 0.0, cy = 0.0, area = 0.0;
    final n = ring.length ~/ 2;
    for (var i = 0, j = n - 1; i < n; j = i++) {
      final f = ring[j * 2] * ring[i * 2 + 1] - ring[i * 2] * ring[j * 2 + 1];
      cx += (ring[j * 2] + ring[i * 2]) * f;
      cy += (ring[j * 2 + 1] + ring[i * 2 + 1]) * f;
      area += f;
    }
    if (area.abs() < 1e-9) return (ring[0], ring[1]);
    final lon = cx / (3 * area);
    return (lon > 180 ? lon - 360 : lon, cy / (3 * area));
  }

  static double _signedArea(Float64List ring) {
    var area = 0.0;
    final n = ring.length ~/ 2;
    for (var i = 0, j = n - 1; i < n; j = i++) {
      area += ring[j * 2] * ring[i * 2 + 1] - ring[i * 2] * ring[j * 2 + 1];
    }
    return area / 2;
  }
}

/// Rings of non-polar polygons that touch both ±180° (Fiji, Chukotka) are
/// shifted to a continuous 0..360° range so planar bounds, hit-tests and
/// centroids stay local. Projection is unaffected (trig is 360°-periodic).
List<Float64List> unwrapAntimeridian(List<Float64List> polygon) {
  final outer = polygon.first;
  var minLon = 180.0, maxLon = -180.0, minLat = 90.0, maxLat = -90.0;
  for (var i = 0; i < outer.length; i += 2) {
    minLon = math.min(minLon, outer[i]);
    maxLon = math.max(maxLon, outer[i]);
    minLat = math.min(minLat, outer[i + 1]);
    maxLat = math.max(maxLat, outer[i + 1]);
  }
  final polar = minLat < -80 || maxLat > 84;
  if (maxLon - minLon <= 180 || polar) return polygon;
  for (final ring in polygon) {
    for (var i = 0; i < ring.length; i += 2) {
      if (ring[i] < 0) ring[i] += 360;
    }
  }
  return polygon;
}

/// Decodes `objects.countries` of a world-atlas TopoJSON topology
/// (quantized, delta-encoded arcs) into [GeoCountry] polygons.
List<GeoCountry> decodeWorldAtlas(String rawJson) {
  final topo = jsonDecode(rawJson) as Map<String, dynamic>;
  final transform = topo['transform'] as Map<String, dynamic>?;
  final scale = (transform?['scale'] as List?)?.cast<num>() ?? const [1, 1];
  final translate =
      (transform?['translate'] as List?)?.cast<num>() ?? const [0, 0];

  final arcs = (topo['arcs'] as List).map((arc) {
    final points = arc as List;
    final out = Float64List(points.length * 2);
    var x = 0.0, y = 0.0;
    for (var i = 0; i < points.length; i++) {
      final p = points[i] as List;
      if (transform != null) {
        x += (p[0] as num).toDouble();
        y += (p[1] as num).toDouble();
        out[i * 2] = x * scale[0] + translate[0];
        out[i * 2 + 1] = y * scale[1] + translate[1];
      } else {
        out[i * 2] = (p[0] as num).toDouble();
        out[i * 2 + 1] = (p[1] as num).toDouble();
      }
    }
    return out;
  }).toList();

  Float64List ring(List indexes) {
    final coords = <double>[];
    for (final raw in indexes) {
      final index = raw as int;
      final arc = arcs[index < 0 ? ~index : index];
      final n = arc.length ~/ 2;
      for (var k = 0; k < n; k++) {
        final i = index < 0 ? n - 1 - k : k;
        if (coords.isNotEmpty && k == 0) continue;
        coords
          ..add(arc[i * 2])
          ..add(arc[i * 2 + 1]);
      }
    }
    return Float64List.fromList(coords);
  }

  final geometries =
      ((topo['objects'] as Map)['countries'] as Map)['geometries'] as List;
  return geometries
      .map((raw) {
        final g = raw as Map<String, dynamic>;
        final arcsField = g['arcs'] as List;
        final polygons = switch (g['type']) {
          'Polygon' => [arcsField.map((r) => ring(r as List)).toList()],
          'MultiPolygon' => arcsField
              .map((p) => (p as List).map((r) => ring(r as List)).toList())
              .toList(),
          _ => <List<Float64List>>[],
        };
        final id = g['id'] as String?;
        return GeoCountry(
          numericId: id,
          iso2: id == null ? null : isoNumericToAlpha2[id],
          name: (g['properties'] as Map?)?['name'] as String? ?? '',
          polygons: polygons.map(unwrapAntimeridian).toList(),
        );
      })
      .where((c) => c.polygons.isNotEmpty)
      .toList();
}
