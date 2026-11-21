import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sim_manager/features/globe/topojson.dart';
import 'package:sim_manager/features/hud/hud_theme.dart';
import 'package:sim_manager/features/settings/theme_mode.dart';
import 'package:sim_manager/main.dart';
import 'package:sim_manager/pages/home_page.dart';

/// Light / dark / follow-system theme mode: switching, persistence, live
/// response to the platform brightness, and light palette contrast.
void main() {
  final atlas = decodeWorldAtlas(
      File('assets/geo/countries-110m.json').readAsStringSync());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpApp(WidgetTester tester,
      {bool phone = false, Key? key}) async {
    tester.view.physicalSize =
        phone ? const Size(1080, 2400) : const Size(1440, 1000);
    tester.view.devicePixelRatio = phone ? 2.625 : 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        SimVaultApp(key: key, home: HomePage(atlasLoader: () async => atlas)));
    await settle(tester);
  }

  ThemeMode appMode(WidgetTester tester) =>
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode!;

  BuildContext home(WidgetTester tester) =>
      tester.element(find.byType(HomePage));

  Brightness shown(WidgetTester tester) => Theme.of(home(tester)).brightness;

  SystemUiOverlayStyle systemBars(WidgetTester tester) => tester
      .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
          find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first)
      .value;

  Future<String?> stored() async => (await SharedPreferences.getInstance())
      .getString(ThemeModeController.prefsKey);

  void platformBrightness(WidgetTester tester, Brightness b) {
    tester.platformDispatcher.platformBrightnessTestValue = b;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('defaults to follow-system when nothing is stored',
      (tester) async {
    platformBrightness(tester, Brightness.light);
    await pumpApp(tester);
    expect(appMode(tester), ThemeMode.system);
    expect(shown(tester), Brightness.light);
    expect(await stored(), isNull);
  });

  testWidgets('desktop switch selects light, dark and system', (tester) async {
    platformBrightness(tester, Brightness.dark);
    await pumpApp(tester);
    expect(find.byKey(const Key('theme-switch')), findsOneWidget);

    await tester.tap(find.byKey(const Key('theme-light')));
    await settle(tester);
    expect(appMode(tester), ThemeMode.light);
    expect(shown(tester), Brightness.light);
    expect(home(tester).hud, same(HudPalette.light));
    expect(systemBars(tester).statusBarIconBrightness, Brightness.dark);
    expect(await stored(), 'light');

    await tester.tap(find.byKey(const Key('theme-dark')));
    await settle(tester);
    expect(appMode(tester), ThemeMode.dark);
    expect(home(tester).hud, same(HudPalette.dark));
    expect(systemBars(tester).statusBarIconBrightness, Brightness.light);
    expect(await stored(), 'dark');

    await tester.tap(find.byKey(const Key('theme-system')));
    await settle(tester);
    expect(appMode(tester), ThemeMode.system);
    expect(shown(tester), Brightness.dark);
    expect(await stored(), 'system');
  });

  testWidgets('phone header opens the theme sheet with 48dp options',
      (tester) async {
    platformBrightness(tester, Brightness.dark);
    await pumpApp(tester, phone: true);
    expect(find.byKey(const Key('theme-switch')), findsNothing);
    await tester.tap(find.byKey(const Key('theme-menu')));
    await settle(tester);
    for (final m in ThemeMode.values) {
      final size = tester.getSize(find.byKey(Key('theme-${m.name}')));
      expect(size.height, greaterThanOrEqualTo(Hud.minTap));
      expect(size.width, greaterThanOrEqualTo(Hud.minTap));
    }
    await tester.tap(find.byKey(const Key('theme-light')));
    await settle(tester);
    expect(appMode(tester), ThemeMode.light);
    expect(shown(tester), Brightness.light);
    expect(await stored(), 'light');
  });

  testWidgets('stored choice is restored by a fresh app instance',
      (tester) async {
    platformBrightness(tester, Brightness.light);
    await pumpApp(tester, key: const ValueKey(1));
    await tester.tap(find.byKey(const Key('theme-dark')));
    await settle(tester);
    expect(shown(tester), Brightness.dark);

    // Throw the app away and start a new one on the same storage.
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, key: const ValueKey(2));
    expect(appMode(tester), ThemeMode.dark);
    expect(shown(tester), Brightness.dark);
  });

  test('controller loads what select() saved, unknown values fall back',
      () async {
    SharedPreferences.setMockInitialValues(
        {ThemeModeController.prefsKey: 'light'});
    final c = ThemeModeController();
    await c.load();
    expect(c.value, ThemeMode.light);
    await c.select(ThemeMode.dark);
    final again = ThemeModeController();
    await again.load();
    expect(again.value, ThemeMode.dark);

    SharedPreferences.setMockInitialValues(
        {ThemeModeController.prefsKey: 'sepia'});
    final bad = ThemeModeController();
    await bad.load();
    expect(bad.value, ThemeMode.system);
  });

  testWidgets('follow-system reacts to a live platform brightness change',
      (tester) async {
    platformBrightness(tester, Brightness.dark);
    await pumpApp(tester);
    expect(shown(tester), Brightness.dark);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await settle(tester);
    expect(appMode(tester), ThemeMode.system);
    expect(shown(tester), Brightness.light);
    expect(home(tester).hud, same(HudPalette.light));
    expect(systemBars(tester).statusBarIconBrightness, Brightness.dark);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await settle(tester);
    expect(shown(tester), Brightness.dark);

    // An explicit choice ignores the platform.
    await tester.tap(find.byKey(const Key('theme-light')));
    await settle(tester);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await settle(tester);
    expect(shown(tester), Brightness.light);
  });

  test('light palette text keeps WCAG AA contrast on its surfaces', () {
    const p = HudPalette.light;
    double lum(Color c) {
      double ch(double v) => v <= .03928
          ? v / 12.92
          : math.pow((v + .055) / 1.055, 2.4).toDouble();
      return .2126 * ch(c.r) + .7152 * ch(c.g) + .0722 * ch(c.b);
    }

    double ratio(Color a, Color b) {
      final x = lum(a), y = lum(b);
      return (math.max(x, y) + .05) / (math.min(x, y) + .05);
    }

    final surfaces = {
      'bg': p.bg,
      'panel': p.panel,
      'glass': Color.alphaBlend(p.glassTint, p.bg),
      'well': Color.alphaBlend(p.well, Color.alphaBlend(p.glassTint, p.bg)),
      'tile': p.tileGradient.last,
      'stage': p.stageGradient.last,
    };
    final texts = {
      'fg': p.fg,
      'muted': p.muted,
      'dim': p.dim,
      'sky': p.sky,
      'rose': p.rose,
      'amber': p.amber,
      'emerald': p.emerald,
      'violet': p.violet,
      'blue': p.blue,
    };
    for (final s in surfaces.entries) {
      for (final t in texts.entries) {
        expect(ratio(t.value, s.value), greaterThanOrEqualTo(4.5),
            reason: '${t.key} on ${s.key}');
      }
    }
    // Filled accents (selected pill / slot) carry onAccent text.
    for (final a in [p.sky, p.amber, p.rose, p.emerald, p.violet, p.blue]) {
      expect(ratio(p.onAccent, a), greaterThanOrEqualTo(4.5));
    }
    expect(ratio(p.nodeLabelFg, p.nodeLabelBg), greaterThanOrEqualTo(4.5));
  });
}
