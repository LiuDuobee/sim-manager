import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sim_manager/features/globe/atlas_globe.dart';
import 'package:sim_manager/features/globe/globe_controller.dart';
import 'package:sim_manager/features/globe/orthographic.dart';
import 'package:sim_manager/features/globe/topojson.dart';

void main() {
  late List<GeoCountry> countries;
  setUpAll(() {
    countries = decodeWorldAtlas(
        File('assets/geo/countries-110m.json').readAsStringSync());
  });

  GeoCountry byIso(String iso) => countries.firstWhere((c) => c.iso2 == iso);

  test('decodes all 177 world-atlas 110m countries with real polygons', () {
    expect(countries.length, 177);
    expect(
        countries.fold<int>(0, (s, c) => s + c.pointCount), greaterThan(10000));
    expect(byIso('CN').contains(116.4, 39.9), isTrue); // Beijing
    expect(byIso('US').contains(-100, 40), isTrue);
    expect(byIso('AU').contains(134, -25), isTrue);
    expect(byIso('CN').contains(-100, 40), isFalse);
    final (lon, lat) = byIso('BR').centroid;
    expect(byIso('BR').contains(lon, lat), isTrue);
  });

  test('antimeridian countries stay local (Fiji, Chukotka)', () {
    final fj = byIso('FJ');
    expect(fj.contains(178, -17.8), isTrue);
    expect(fj.contains(-179.85, -16.2), isTrue);
    expect(fj.contains(0, -16.5), isFalse);
    final (lon, _) = fj.centroid;
    expect(lon.abs(), greaterThan(170));
    expect(byIso('RU').contains(-175, 66), isTrue);
    expect(byIso('RU').contains(0, 66), isFalse);
  });

  group('orthographic projection', () {
    final proj = Orthographic(
        centerLon: 110,
        centerLat: 24,
        radius: 100,
        origin: const Offset(200, 200));

    test('center maps to origin, antipode is culled', () {
      expect(proj.project(110, 24), const Offset(200, 200));
      expect(proj.project(-70, -24), isNull);
      expect(proj.projectRaw(-70, -24).$3, lessThan(0));
    });

    test('visibility is exactly center angle < 90°', () {
      expect(proj.isVisible(110 + 89, 0), isTrue);
      expect(proj.isVisible(110 + 91 + 10, 0), isFalse);
      final eq = Orthographic(
          centerLon: 0, centerLat: 0, radius: 1, origin: Offset.zero);
      expect(eq.isVisible(89.9, 0), isTrue);
      expect(eq.isVisible(90.1, 0), isFalse);
    });

    test('invert is the inverse of project on the near side', () {
      final p = proj.project(139.65, 35.68)!;
      final (lon, lat) = proj.invert(p)!;
      expect(lon, closeTo(139.65, 1e-6));
      expect(lat, closeTo(35.68, 1e-6));
      expect(proj.invert(const Offset(0, 0)), isNull);
    });

    test('far-side countries produce no path, near-side ones do', () {
      final ring = byIso('BR').polygons.first.first;
      expect(proj.clippedRing(ring), isNull);
      expect(proj.clippedRing(byIso('CN').polygons.first.first), isNotNull);
    });

    test('node markers are back-face culled', () {
      const nodes = [
        GlobeNode(
            code: 'CN', lon: 116.4, lat: 39.9, count: 1, color: Colors.red),
        GlobeNode(code: 'US', lon: -74, lat: 40.7, count: 1, color: Colors.red),
      ];
      expect(visibleNodes(proj, nodes).map((e) => e.$1.code), ['CN']);
      final us = Orthographic(
          centerLon: -90, centerLat: 30, radius: 100, origin: Offset.zero);
      expect(visibleNodes(us, nodes).map((e) => e.$1.code), ['US']);
    });
  });

  test('flyTo eases to the target in 650 ms along the shortest path', () {
    final c = GlobeController(centerLon: 170, centerLat: 0);
    c.flyTo(-170, 35, zoom: 1.5);
    c.tick(Duration.zero);
    c.tick(const Duration(milliseconds: 100));
    expect(c.centerLon, greaterThan(170)); // crosses the antimeridian eastward
    c.tick(const Duration(milliseconds: 700));
    expect(c.isFlying, isFalse);
    expect(c.centerLon, closeTo(-170, 1e-9));
    expect(c.centerLat, closeTo(35, 1e-9));
    expect(c.zoom, closeTo(1.5, 1e-9));
    expect(c.spinning, isFalse);
  });

  test('auto-spin advances longitude only while not dragging', () {
    final c = GlobeController(centerLon: 0);
    c.tick(Duration.zero);
    c.tick(const Duration(seconds: 1));
    expect(c.centerLon, closeTo(GlobeController.spinDegreesPerSecond, 1e-9));
    c.setDragging(true);
    c.tick(const Duration(seconds: 2));
    expect(c.centerLon, closeTo(GlobeController.spinDegreesPerSecond, 1e-9));
  });

  test('wrapLonDelta picks the short way round', () {
    expect(wrapLonDelta(340), -20);
    expect(wrapLonDelta(-200), 160);
  });

  testWidgets('only primary clicks/taps select a country', (tester) async {
    final hits = <String?>[];
    final c =
        GlobeController(centerLon: 116.4, centerLat: 39.9, spinning: false);
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox.square(
          dimension: 400,
          child: AtlasGlobe(
            controller: c,
            countries: countries,
            nodes: const [],
            onCountryTap: (iso, _, __, ___) => hits.add(iso),
          ),
        ),
      ),
    ));
    final center = tester.getCenter(find.byType(AtlasGlobe));
    for (final button in [kSecondaryMouseButton, kMiddleMouseButton]) {
      final g = await tester.startGesture(center,
          kind: PointerDeviceKind.mouse, buttons: button);
      await g.up();
      await tester.pump();
    }
    expect(hits, isEmpty);
    await tester.tapAt(center);
    await tester.pump();
    expect(hits, ['CN']);
  });
}
